import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/theme.dart';
import '../models/file_item.dart';
import '../providers/browser_provider.dart';
import '../providers/settings_provider.dart';
import '../services/archive_service.dart';
import '../services/file_service.dart';
import 'dialogs.dart';
import 'optimizer_screen.dart';
import 'transfer_screen.dart';
import 'widgets/file_icon.dart';
import 'widgets/file_tile.dart';
import 'widgets/storage_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();

  bool _extracting = false;
  Timer? _purgeTimer;
  List<TrashRecord> _pendingPurge = const [];

  BrowserNotifier get _n => ref.read(browserProvider.notifier);
  FileService get _fs => ref.read(fileServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purgeTimer?.cancel(); // pending ZIP Trash mein safe rehti hai
    _search.dispose();
    super.dispose();
  }

  /// Settings se permission dekar wapas aao to files khud load ho jayein.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(browserProvider).needsPermission) {
      _n.init();
    }
  }

  // ------------------------------------------------------------------ helpers

  void _toast(String msg, {SnackBarAction? action}) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    final c = m.showSnackBar(
      SnackBar(
        content: Text(msg),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    Future.delayed(const Duration(seconds: 5), c.close);
  }

  List<FileItem> get _selectedItems {
    final st = ref.read(browserProvider);
    return st.items.where((i) => st.selected.contains(i.path)).toList();
  }

  bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  // ------------------------------------------------------------------ actions

  Future<void> _rename(FileItem item) async {
    final name = await showNameDialog(
      context,
      title: 'Rename',
      confirm: 'Save',
      initial: item.name,
      selectBase: !item.isDir,
    );
    if (name == null || name == item.name) return;
    final err = await _n.rename(item, name);
    if (!mounted) return;
    _toast(err ?? 'Rename ho gaya ✓');
  }

  Future<void> _batchRename(List<FileItem> items) async {
    final opts = await showBatchRenameDialog(context, items);
    if (opts == null) return;
    final r = await _n.batchRename(items, opts);
    if (!mounted) return;
    _toast(
      '${r.ok} files rename hui'
      '${r.failed > 0 ? ' • ${r.failed} nahi ho saki' : ' ✓'}',
    );
  }

  Future<void> _renameSelected() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    if (items.length == 1) {
      await _rename(items.first);
    } else {
      await _batchRename(items);
    }
  }

  Future<void> _trash(List<FileItem> items) async {
    if (items.isEmpty) return;
    final records = await _n.trash(items);
    if (!mounted) return;
    if (records.isEmpty) {
      _toast('Delete nahi ho saka');
      return;
    }
    _toast(
      '${records.length} item Trash mein gaya',
      action: SnackBarAction(
        label: 'UNDO',
        textColor: AppColors.sky,
        onPressed: () => _n.undo(records),
      ),
    );
  }

  /// ⭐ Important mark / unmark
  void _star(List<FileItem> items) {
    if (items.isEmpty) return;
    final added = _n.toggleFavorites(items);
    _n.clearSelection();
    _toast(added ? '⭐ Important mein add hua' : 'Important se hata diya');
  }

  Future<void> _newFolder() async {
    final name = await showNameDialog(
      context,
      title: 'Naya Folder',
      confirm: 'Banayein',
      icon: Icons.create_new_folder_rounded,
      hint: 'Folder ka naam',
    );
    if (name == null) return;
    final err = await _n.createFolder(name);
    if (!mounted) return;
    if (err != null) _toast(err);
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Trash saaf karein?'),
        content: const Text(
          'Trash mein jo files hain wo hamesha ke liye delete ho jayengi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Saaf karein'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final freed = await _n.emptyTrash();
    if (!mounted) return;
    ref.invalidate(storageStatsProvider);
    _toast('${formatSize(freed)} jagah khali hui ✓');
  }

  Future<void> _openItem(FileItem item) async {
    if (item.isDir) {
      _n.open(item.path);
      return;
    }
    if (item.isExtractable) {
      await _extract(item);
      return;
    }
    final r = await OpenFilex.open(item.path);
    if (!mounted) return;
    if (r.type != ResultType.done) {
      final e = item.ext;
      _toast(
        (e == 'rar' || e == '7z')
            ? 'RAR / 7z extract abhi support nahi (${ArchiveService.supportedHint} chalte hain)'
            : 'Is file ko kholne wali app nahi mili',
      );
    }
  }

  // ------------------------------------------------------------ ZIP extractor

  /// ZIP par tap => foran naye folder mein extract (alag isolate mein, UI smooth).
  Future<void> _extract(FileItem item) async {
    if (_extracting) return;
    _extracting = true;
    final progress = ValueNotifier<(int, int)?>(null);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExtractDialog(name: item.name, progress: progress),
    ));

    ExtractResult? res;
    String? err;
    try {
      res = await _n.extractArchive(
        item,
        onProgress: (d, t) => progress.value = (d, t),
      );
    } on FileOpException catch (e) {
      err = e.message;
    } catch (_) {
      err = 'Extract nahi ho saka';
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    _extracting = false;
    if (!mounted) return;
    ref.invalidate(storageStatsProvider);

    if (res == null) {
      _toast(err ?? 'Extract nahi ho saka');
      return;
    }
    if (ref.read(settingsProvider).autoDeleteZip) {
      await _deleteZip(item, res);
    } else {
      await _showExtractDone(item, res);
    }
  }

  Future<void> _showExtractDone(FileItem item, ExtractResult res) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ExtractDoneSheet(item: item, result: res),
    );
    if (!mounted) return;
    if (choice == 'open') {
      _n.open(res.dest);
    } else if (choice == 'delete') {
      await _deleteZip(item, res);
    }
  }

  /// ZIP ko Trash mein bhejta hai (5 sec Undo). Undo na hua to hamesha ke liye
  /// delete, taake storage sach mein bache.
  Future<void> _deleteZip(FileItem item, ExtractResult res) async {
    await _flushPurge();
    final records = await _n.trash([item]);
    if (!mounted) return;
    if (records.isEmpty) {
      _toast('Extract ho gaya, par ZIP delete nahi ho saka');
      return;
    }
    _pendingPurge = records;
    _purgeTimer = Timer(const Duration(seconds: 5), _flushPurge);
    _toast(
      'Extract ho gaya ✓ ZIP delete • ${formatSize(item.size)} bachi',
      action: SnackBarAction(
        label: 'UNDO',
        textColor: AppColors.sky,
        onPressed: () {
          _purgeTimer?.cancel();
          final r = _pendingPurge;
          _pendingPurge = const [];
          _n.undo(r);
          ref.invalidate(storageStatsProvider);
        },
      ),
    );
  }

  Future<void> _flushPurge() async {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    final r = _pendingPurge;
    if (r.isEmpty) return;
    _pendingPurge = const [];
    await _n.purge(r);
    if (mounted) ref.invalidate(storageStatsProvider);
  }

  Future<void> _openOptimizer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OptimizerScreen()),
    );
    if (!mounted) return;
    _n.refresh();
    ref.invalidate(storageStatsProvider);
  }

  Future<void> _paste() async {
    final r = await _n.pasteHere();
    if (!mounted) return;
    _toast(
      '${r.ok} item move hue'
      '${r.failed > 0 ? ' • ${r.failed} nahi ho sake' : ' ✓'}',
    );
  }

  Future<void> _openTransfer() async {
    final path = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const TransferScreen()),
    );
    if (path != null) _n.open(path);
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(browserProvider);
    ref.listen<String>(browserProvider.select((s) => s.query), (prev, next) {
      if (next.isEmpty && _search.text.isNotEmpty) _search.clear();
    });

    final wide = MediaQuery.sizeOf(context).width >= 860;
    final root = _fs.root.path;
    final canExit =
        !(st.selecting || st.isFiltering || st.moving || st.path != root);

    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _n.back();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2): () {
            if (!_typing) _renameSelected();
          },
          const SingleActivator(LogicalKeyboardKey.delete): () {
            if (!_typing) _trash(_selectedItems);
          },
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
            if (!_typing) _n.selectAll();
          },
          const SingleActivator(LogicalKeyboardKey.escape): () => _n.back(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    _Sidebar(
                      onTransfer: _openTransfer,
                      onOptimizer: _openOptimizer,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _buildHeader(st, wide),
                        _buildCrumbs(st, root),
                        Expanded(child: _buildBody(st, wide)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            floatingActionButton: (st.selecting || wide)
                ? null
                : FloatingActionButton.extended(
                    onPressed: _openTransfer,
                    icon: const Icon(Icons.wifi_tethering_rounded),
                    label: const Text(
                      'Wireless',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
            bottomNavigationBar: st.moving ? _buildMoveBar(st) : null,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- header

  Widget _buildHeader(BrowserState st, bool wide) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6CC4F8), AppColors.skyDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x331E88E5),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: st.selecting ? _selectionBar(st) : _normalBar(st),
        ),
      ),
    );
  }

  Widget _menuRow(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 20, color: AppColors.skyDark),
          const SizedBox(width: 12),
          Text(text),
        ],
      );

  Widget _normalBar(BrowserState st) {
    final subtitle = st.isFiltering
        ? (st.favoritesOnly ? '⭐ Important' : 'Poori storage mein search')
        : (st.path == _fs.root.path ? 'Home' : p.basename(st.path));

    return Column(
      key: const ValueKey('normal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SwiftFiles',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withAlpha(224),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<SortMode>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort_rounded, color: Colors.white),
              onSelected: _n.setSort,
              itemBuilder: (_) => [
                for (final m in SortMode.values)
                  CheckedPopupMenuItem<SortMode>(
                    value: m,
                    checked: st.sort == m,
                    child: Text(m.label),
                  ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Menu',
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (v) {
                switch (v) {
                  case 'folder':
                    _newFolder();
                  case 'refresh':
                    _n.refresh();
                    ref.invalidate(storageStatsProvider);
                  case 'trash':
                    _emptyTrash();
                  case 'optimizer':
                    _openOptimizer();
                  case 'hidden':
                    _n.toggleHidden();
                  case 'time':
                    ref
                        .read(settingsProvider.notifier)
                        .setShowTime(!ref.read(settingsProvider).showTime);
                  case 'autozip':
                    final enable = !ref.read(settingsProvider).autoDeleteZip;
                    ref.read(settingsProvider.notifier).setAutoDeleteZip(enable);
                    _toast(
                      enable
                          ? 'Ab extract ke baad ZIP khud delete hogi (Undo milega)'
                          : 'Ab extract ke baad ZIP rehne di jayegi',
                    );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'folder',
                  enabled: !st.isFiltering,
                  child: _menuRow(Icons.create_new_folder_outlined, 'Naya folder'),
                ),
                PopupMenuItem(
                  value: 'refresh',
                  child: _menuRow(Icons.refresh_rounded, 'Refresh'),
                ),
                PopupMenuItem(
                  value: 'trash',
                  child: _menuRow(Icons.delete_sweep_outlined, 'Trash saaf karein'),
                ),
                PopupMenuItem(
                  value: 'optimizer',
                  child: _menuRow(
                    Icons.cleaning_services_outlined,
                    'Storage Optimizer',
                  ),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'hidden',
                  checked: st.showHidden,
                  child: const Text('Hidden files dikhayein'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'time',
                  checked: ref.read(settingsProvider).showTime,
                  child: const Text('Time dikhayein'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'autozip',
                  checked: ref.read(settingsProvider).autoDeleteZip,
                  child: const Text('Extract ke baad ZIP delete'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: _n.setQuery,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Files dhundein...',
            hintStyle: const TextStyle(color: AppColors.muted),
            prefixIcon:
                const Icon(Icons.search_rounded, color: AppColors.skyDark),
            suffixIcon: st.query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _n.setQuery('');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in FileCategory.values) ...[
                _CatChip(
                  label: c.label,
                  icon: categoryIcon(c),
                  selected: st.category == c &&
                      !(c == FileCategory.all && st.favoritesOnly),
                  onTap: () => c == FileCategory.all
                      ? _n.clearFilters()
                      : _n.setCategory(c),
                ),
                if (c == FileCategory.all)
                  _CatChip(
                    label: 'Favorites',
                    icon: Icons.star_rounded,
                    selected: st.favoritesOnly,
                    onTap: _n.toggleFavoritesView,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectionBar(BrowserState st) {
    final one = st.selected.length == 1;
    final favs = ref.watch(settingsProvider).favorites;
    final allFav = st.selected.isNotEmpty && st.selected.every(favs.contains);

    Widget act(IconData i, String tip, VoidCallback f) => IconButton(
          onPressed: f,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          color: Colors.white,
          icon: Icon(i, size: 24),
        );

    return SizedBox(
      key: const ValueKey('selection'),
      height: 76,
      child: Row(
        children: [
          act(Icons.close_rounded, 'Cancel', _n.clearSelection),
          Expanded(
            child: Text(
              '${st.selected.length} selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          act(
            allFav ? Icons.star_rounded : Icons.star_outline_rounded,
            allFav ? 'Important se hatayein' : 'Important mark karein',
            () => _star(_selectedItems),
          ),
          act(Icons.select_all_rounded, 'Sab select (Ctrl+A)', _n.selectAll),
          act(
            Icons.drive_file_rename_outline_rounded,
            one ? 'Rename (F2)' : 'Batch rename',
            _renameSelected,
          ),
          act(Icons.drive_file_move_outline_rounded, 'Move', _n.startMove),
          act(
            Icons.delete_outline_rounded,
            'Delete',
            () => _trash(_selectedItems),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- breadcrumb

  Widget _crumb(String label, String path, bool last) => Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: last ? null : () => _n.open(path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: last ? FontWeight.w800 : FontWeight.w600,
                color: last ? AppColors.ink : AppColors.skyDark,
              ),
            ),
          ),
        ),
      );

  Widget _buildCrumbs(BrowserState st, String root) {
    if (st.isFiltering) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                st.favoritesOnly
                    ? '${st.items.length} important'
                    : '${st.items.length} results • ${st.sort.label}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _n.clearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ],
        ),
      );
    }

    final rel = p.relative(st.path, from: root);
    final parts = rel == '.' ? <String>[] : p.split(rel);
    final crumbs = <Widget>[_crumb('Home', root, parts.isEmpty)];
    var acc = root;
    for (var i = 0; i < parts.length; i++) {
      acc = p.join(acc, parts[i]);
      crumbs.add(const Center(
        child: Icon(Icons.chevron_right_rounded,
            size: 18, color: AppColors.muted),
      ));
      crumbs.add(_crumb(parts[i], acc, i == parts.length - 1));
    }

    return SizedBox(
      height: 50,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: box.maxWidth > 28 ? box.maxWidth - 28 : 0,
            ),
            child: Row(children: crumbs),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- body

  Widget _buildBody(BrowserState st, bool wide) {
    if (st.needsPermission) return _PermissionView(onGrant: _n.init);
    if (st.error != null) {
      return _EmptyState(
        icon: Icons.lock_outline_rounded,
        title: st.error!,
        subtitle: 'Permission check karein ya doosra folder kholein',
      );
    }

    final list = st.items;
    final side = wide ? 24.0 : 12.0;
    // Mobile par Home folder ke sab se upar storage indicator (PC par sidebar mein hota hai)
    final showStorage = !wide && !st.isFiltering && st.path == _fs.root.path;

    return Column(
      children: [
        SizedBox(
          height: 3,
          child: st.loading ? const LinearProgressIndicator(minHeight: 3) : null,
        ),
        Expanded(
          child: (!st.loading && list.isEmpty)
              ? _EmptyState(
                  icon: st.favoritesOnly
                      ? Icons.star_outline_rounded
                      : st.isFiltering
                      ? Icons.search_off_rounded
                      : Icons.folder_open_rounded,
                  title: st.favoritesOnly
                      ? 'Abhi koi Important file nahi'
                      : st.isFiltering
                          ? 'Kuch nahi mila'
                          : 'Ye folder khali hai',
                  subtitle: st.favoritesOnly
                      ? 'File select karke ⭐ dabayein'
                      : st.isFiltering
                      ? 'Doosra naam ya category try karein'
                      : 'Yahan abhi koi file nahi',
                )
              : RefreshIndicator(
                  color: AppColors.skyDark,
                  onRefresh: () async {
                    ref.invalidate(storageStatsProvider);
                    await _n.refresh();
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(side, 4, side, 110),
                    itemCount: list.length + (showStorage ? 1 : 0),
                    itemBuilder: (context, idx) {
                      if (showStorage && idx == 0) {
                        return StorageCard(onTap: _openOptimizer);
                      }
                      final it = list[showStorage ? idx - 1 : idx];
                      return FileTile(
                        item: it,
                        selected: st.selected.contains(it.path),
                        selecting: st.selecting,
                        dim: st.moveBasket.contains(it.path),
                        showPath: st.isFiltering,
                        showTime: ref.watch(settingsProvider).showTime,
                        isFav: ref
                            .watch(settingsProvider)
                            .favorites
                            .contains(it.path),
                        onStar: () => _star([it]),
                        wide: wide,
                        onTap: () {
                          if (st.selecting) {
                            _n.toggle(it.path);
                          } else {
                            _openItem(it);
                          }
                        },
                        onLongPress: () => _n.toggle(it.path),
                        onCheck: () => _n.toggle(it.path),
                        onRename: () => _rename(it),
                        onDelete: () => _trash([it]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ move bar

  Widget _buildMoveBar(BrowserState st) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F1E88E5),
            blurRadius: 20,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${st.moveBasket.length} item move karne hain',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'Destination folder kholein, phir "Yahan paste" dabayein',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: _n.cancelMove, child: const Text('Cancel')),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste_go_rounded, size: 18),
              label: const Text('Yahan paste'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Chhote helper widgets
// =============================================================================

class _CatChip extends StatelessWidget {
  const _CatChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.skyDark : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withAlpha(56),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.onTransfer, required this.onOptimizer});

  final VoidCallback onTransfer;
  final VoidCallback onOptimizer;

  IconData _icon(String label) => switch (label) {
        'Home' => Icons.home_rounded,
        'Download' || 'Downloads' => Icons.download_rounded,
        'DCIM' => Icons.photo_camera_rounded,
        'Pictures' => Icons.image_rounded,
        'Movies' || 'Videos' => Icons.movie_rounded,
        'Music' => Icons.music_note_rounded,
        'Documents' => Icons.description_rounded,
        'Desktop' => Icons.desktop_windows_rounded,
        _ => Icons.folder_rounded,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(browserProvider);
    final locs = ref.read(fileServiceProvider).quickLocations();

    return Container(
      width: 252,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141E88E5),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6CC4F8), AppColors.skyDark],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Text(
                'SwiftFiles',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              'LOCATIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: st.favoritesOnly
                        ? AppColors.skySoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => ref
                          .read(browserProvider.notifier)
                          .toggleFavoritesView(),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Row(
                          children: [
                            Icon(Icons.star_rounded,
                                size: 21, color: Color(0xFFFFB300)),
                            SizedBox(width: 12),
                            Text(
                              'Favorites',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                for (final l in locs)
                  Builder(builder: (context) {
                    final active = !st.isFiltering && p.equals(st.path, l.path);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Material(
                        color: active ? AppColors.skySoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              ref.read(browserProvider.notifier).open(l.path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _icon(l.label),
                                  size: 21,
                                  color: active
                                      ? AppColors.skyDark
                                      : AppColors.muted,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  l.label,
                                  style: TextStyle(
                                    fontWeight:
                                        active ? FontWeight.w700 : FontWeight.w600,
                                    color: active
                                        ? AppColors.skyDark
                                        : AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const StorageCard(compact: true),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onOptimizer,
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Storage Optimizer'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              side: const BorderSide(color: AppColors.sky),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onTransfer,
            icon: const Icon(Icons.wifi_tethering_rounded),
            label: const Text('Wireless Transfer'),
          ),
          const SizedBox(height: 14),
          const Text(
            'F2 Rename  •  Del Delete  •  Ctrl+A Sab select',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: AppColors.skySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.skyDark),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: AppColors.skySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.folder_shared_rounded,
                size: 48,
                color: AppColors.skyDark,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Storage access chahiye',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Files dikhane ke liye "All files access" permission zaroori hai. '
              'Neeche button dabayein, settings mein SwiftFiles ko ON karein, '
              'phir wapas aa jayein.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Permission dein'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtractDialog extends StatelessWidget {
  const _ExtractDialog({required this.name, required this.progress});

  final String name;
  final ValueNotifier<(int, int)?> progress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: ValueListenableBuilder<(int, int)?>(
              valueListenable: progress,
              builder: (context, v, _) {
                final done = v?.$1 ?? 0;
                final total = v?.$2 ?? 0;
                final determinate = total > 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.skySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.unarchive_rounded,
                            color: AppColors.skyDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Extract ho raha hai...',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: determinate ? done / total : null,
                        minHeight: 8,
                        backgroundColor: AppColors.skySoft,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      determinate ? '$done / $total files' : 'Archive khul raha hai',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtractDoneSheet extends ConsumerWidget {
  const _ExtractDoneSheet({required this.item, required this.result});

  final FileItem item;
  final ExtractResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(settingsProvider).autoDeleteZip;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.success.withAlpha(38),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Extract ho gaya ✓',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        '${result.extracted} files • ${formatSize(result.bytes)}'
                        '${result.failed > 0 ? ' • ${result.failed} nahi ho saki' : ''}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Naya folder: ${p.basename(result.dest)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'open'),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Folder kholein'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text('ZIP delete karein (${formatSize(item.size)} bachayein)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: auto,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setAutoDeleteZip(v),
              title: const Text(
                'Aaindah extract ke baad ZIP khud delete karein',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('ZIP rehne dein'),
            ),
          ],
        ),
      ),
    );
  }
}
