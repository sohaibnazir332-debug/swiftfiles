import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../core/format.dart';
import '../core/theme.dart';
import '../models/file_item.dart';
import '../providers/browser_provider.dart';
import '../providers/settings_provider.dart';
import '../services/file_service.dart';
import '../services/optimizer_service.dart';
import 'widgets/file_icon.dart';
import 'widgets/storage_card.dart';

enum _Tab { large, dupes }

/// Storage Optimizer: badi files aur duplicate files ek jagah, safe delete (Undo) ke sath.
class OptimizerScreen extends ConsumerStatefulWidget {
  const OptimizerScreen({super.key});

  @override
  ConsumerState<OptimizerScreen> createState() => _OptimizerScreenState();
}

class _OptimizerScreenState extends ConsumerState<OptimizerScreen> {
  late final OptimizerService _opt;
  late final FileService _fs;
  late final BrowserNotifier _n;

  ScanResult? _result;
  ScanProgress? _progress;
  bool _scanning = false;
  String? _error;
  _Tab _tab = _Tab.large;
  final Set<String> _sel = {};
  int _trashBytes = 0;

  @override
  void initState() {
    super.initState();
    _opt = ref.read(optimizerServiceProvider);
    _fs = ref.read(fileServiceProvider);
    _n = ref.read(browserProvider.notifier);
    _loadTrash();
  }

  @override
  void dispose() {
    _opt.cancel();
    super.dispose();
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

  Future<void> _loadTrash() async {
    final s = await _fs.trashSize();
    if (mounted) setState(() => _trashBytes = s);
  }

  // --------------------------------------------------------------------- scan

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _progress = const ScanProgress('Shuru ho raha hai', 0, 0);
      _sel.clear();
    });
    try {
      final r = await _opt.scan(
        showHidden: ref.read(settingsProvider).showHidden,
        onProgress: (pr) {
          if (mounted) setState(() => _progress = pr);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _scanning = false;
        if (r.large.isEmpty && r.groups.isNotEmpty) _tab = _Tab.dupes;
      });
    } catch (e) {
      if (!mounted) return;
      final cancelled = e is FileOpException && e.message == 'cancelled';
      setState(() {
        _scanning = false;
        _error = cancelled ? null : 'Scan poora nahi ho saka';
      });
    }
  }

  // ---------------------------------------------------------------- selection

  List<FileItem> _selectedItems() {
    final r = _result;
    if (r == null) return [];
    final seen = <String>{};
    final out = <FileItem>[];
    for (final f in r.large) {
      if (_sel.contains(f.path) && seen.add(f.path)) out.add(f);
    }
    for (final g in r.groups) {
      for (final f in g.files) {
        if (_sel.contains(f.path) && seen.add(f.path)) {
          out.add(FileItem(
            path: f.path,
            isDir: false,
            size: g.size,
            modified: f.modified,
          ));
        }
      }
    }
    return out;
  }

  void _toggleLarge(FileItem f) {
    setState(() {
      if (!_sel.remove(f.path)) _sel.add(f.path);
    });
  }

  void _toggleDup(DupGroup g, DupFile f) {
    if (_sel.contains(f.path)) {
      setState(() => _sel.remove(f.path));
      return;
    }
    final selectedInGroup = g.files.where((x) => _sel.contains(x.path)).length;
    if (selectedInGroup >= g.files.length - 1) {
      _toast('Har group mein kam az kam ek copy rakhni zaroori hai');
      return;
    }
    setState(() => _sel.add(f.path));
  }

  /// Har duplicate group mein sabse purani copy rakho, baaki select karo
  void _smartSelect() {
    final r = _result;
    if (r == null) return;
    setState(() {
      _sel.clear();
      for (final g in r.groups) {
        for (var i = 1; i < g.files.length; i++) {
          _sel.add(g.files[i].path);
        }
      }
    });
  }

  // ------------------------------------------------------------------- delete

  ScanResult _without(ScanResult r, Set<String> gone) {
    final groups = <DupGroup>[];
    for (final g in r.groups) {
      final left = g.files.where((f) => !gone.contains(f.path)).toList();
      if (left.length > 1) groups.add(DupGroup(g.size, left));
    }
    return ScanResult(
      large: r.large.where((f) => !gone.contains(f.path)).toList(),
      groups: groups,
      scanned: r.scanned,
    );
  }

  Future<void> _deleteSelected() async {
    final r = _result;
    if (r == null || _sel.isEmpty) return;

    // Safety: kisi duplicate group ki saari copies kabhi delete nahi hongi
    final keep = <String>{};
    for (final g in r.groups) {
      if (g.files.every((f) => _sel.contains(f.path))) {
        keep.add(g.files.first.path);
      }
    }
    final items = _selectedItems().where((i) => !keep.contains(i.path)).toList();
    if (items.isEmpty) return;

    final snapshot = r;
    final records = await _n.trash(items);
    if (!mounted) return;
    if (records.isEmpty) {
      _toast('Delete nahi ho saka');
      return;
    }

    final gone = records.map((x) => x.original).toSet();
    final bytes = items
        .where((i) => gone.contains(i.path))
        .fold<int>(0, (s, i) => s + i.size);

    setState(() {
      _result = _without(r, gone);
      _sel.clear();
    });
    _loadTrash();
    ref.invalidate(storageStatsProvider);

    _toast(
      '${records.length} file Trash mein • ${formatSize(bytes)}'
      '${keep.isNotEmpty ? ' • ${keep.length} copy bacha li' : ''}',
      action: SnackBarAction(
        label: 'UNDO',
        textColor: AppColors.sky,
        onPressed: () async {
          await _n.undo(records);
          if (!mounted) return;
          setState(() => _result = snapshot);
          _loadTrash();
          ref.invalidate(storageStatsProvider);
        },
      ),
    );
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Trash saaf karein?'),
        content: Text(
          'Trash mein ${formatSize(_trashBytes)} ki files hain. '
          'Ye hamesha ke liye delete ho jayengi.',
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
    _loadTrash();
    ref.invalidate(storageStatsProvider);
    _toast('${formatSize(freed)} jagah khali hui ✓');
  }

  Future<void> _open(String path) async {
    final r = await OpenFilex.open(path);
    if (!mounted) return;
    if (r.type != ResultType.done) _toast('Is file ko kholne wali app nahi mili');
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final selItems = _selectedItems();
    final selBytes = selItems.fold<int>(0, (s, i) => s + i.size);

    return Scaffold(
      body: Column(
        children: [
          _Header(onBack: () => Navigator.pop(context)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 0),
                      sliver: SliverToBoxAdapter(child: _top(r)),
                    ),
                    if (r != null) ..._content(r),
                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          _sel.isEmpty ? null : _selectionBar(selItems.length, selBytes),
    );
  }

  Widget _top(ScanResult? r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StorageCard(),
        const SizedBox(height: 10),
        _scanCard(r),
        if (_trashBytes > 0) ...[
          const SizedBox(height: 10),
          _trashCard(),
        ],
        if (r != null) ...[
          const SizedBox(height: 14),
          _tabs(r),
          if (_tab == _Tab.dupes && r.groups.isNotEmpty) ...[
            const SizedBox(height: 10),
            _dupSummary(r),
          ],
          if (_tab == _Tab.large && r.large.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                '${formatSize(OptimizerService.largeMinBytes)} se badi files, '
                'sabse badi pehle',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141E88E5),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      );

  Widget _scanCard(ScanResult? r) {
    if (_scanning) {
      final pr = _progress;
      final done = pr?.done ?? 0;
      final total = pr?.total ?? 0;
      final determinate = total > 0;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              pr?.phase ?? 'Scan ho raha hai',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              determinate ? '$done / $total' : '$done files mili...',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: determinate ? done / total : null,
                minHeight: 8,
                backgroundColor: AppColors.skySoft,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _opt.cancel,
                child: const Text('Rok dein'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            r == null ? 'Storage scan karein' : 'Scan mukammal ✓',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            r == null
                ? 'Badi files aur duplicate (ek jaisi) files dhoondi jayengi. '
                    'Delete karne se pehle aap khud chunenge, aur Undo bhi milega.'
                : '${r.scanned} files check hui • '
                    '${r.groups.length} duplicate groups • '
                    '${formatSize(r.wastedTotal)} jagah bachayi ja sakti hai',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startScan,
            icon: Icon(r == null ? Icons.search_rounded : Icons.refresh_rounded),
            label: Text(r == null ? 'Scan shuru karein' : 'Dobara scan karein'),
          ),
        ],
      ),
    );
  }

  Widget _trashCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: _cardDeco(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.danger.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.delete_sweep_rounded,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trash',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${formatSize(_trashBytes)} abhi bhi jagah gher rahi hai',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          TextButton(onPressed: _emptyTrash, child: const Text('Saaf karein')),
        ],
      ),
    );
  }

  Widget _tabs(ScanResult r) {
    Widget chip(_Tab t, String label, IconData icon) {
      final sel = _tab == t;
      return Expanded(
        child: Material(
          color: sel ? AppColors.skyDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              _tab = t;
              _sel.clear();
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: sel ? Colors.white : AppColors.skyDark,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: sel ? Colors.white : AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(_Tab.large, 'Badi files (${r.large.length})',
            Icons.sd_storage_rounded),
        const SizedBox(width: 10),
        chip(_Tab.dupes, 'Duplicates (${r.groups.length})',
            Icons.content_copy_rounded),
      ],
    );
  }

  Widget _dupSummary(ScanResult r) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.skySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${formatSize(r.wastedTotal)} faltu jagah',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.skyDark,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _smartSelect,
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('Smart select'),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(ScanResult r) {
    if (_tab == _Tab.large) {
      if (r.large.isEmpty) {
        return [
          const SliverToBoxAdapter(
            child: _Empty(
              icon: Icons.check_circle_outline_rounded,
              title: 'Koi bahut badi file nahi mili',
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList.builder(
            itemCount: r.large.length,
            itemBuilder: (context, i) {
              final f = r.large[i];
              return _SelRow(
                item: f,
                selected: _sel.contains(f.path),
                subtitle: '${formatSize(f.size)} • ${formatDate(f.modified)}'
                    ' • ${_where(f.path)}',
                onTap: () => _toggleLarge(f),
                onOpen: () => _open(f.path),
              );
            },
          ),
        ),
      ];
    }

    if (r.groups.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: _Empty(
            icon: Icons.check_circle_outline_rounded,
            title: 'Koi duplicate file nahi mili',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        sliver: SliverList.builder(
          itemCount: r.groups.length,
          itemBuilder: (context, i) => _groupCard(r.groups[i]),
        ),
      ),
    ];
  }

  String _where(String path) {
    final rel = p.relative(p.dirname(path), from: _fs.root.path);
    return rel == '.' ? 'Home' : rel;
  }

  Widget _groupCard(DupGroup g) {
    final name = p.basename(g.files.first.path);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.skySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${g.files.length} copies • ${formatSize(g.wasted)} faltu',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.skyDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < g.files.length; i++)
            _SelRow(
              flat: true,
              item: FileItem(
                path: g.files[i].path,
                isDir: false,
                size: g.size,
                modified: g.files[i].modified,
              ),
              selected: _sel.contains(g.files[i].path),
              subtitle: '${i == 0 ? 'Sabse purani • ' : ''}'
                  '${formatDate(g.files[i].modified)} • ${_where(g.files[i].path)}',
              onTap: () => _toggleDup(g, g.files[i]),
              onOpen: () => _open(g.files[i].path),
            ),
        ],
      ),
    );
  }

  Widget _selectionBar(int count, int bytes) {
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
                    '$count selected',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${formatSize(bytes)} jagah bachegi',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(_sel.clear),
              child: const Text('Clear'),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: _deleteSelected,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 8,
        16,
        22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6CC4F8), AppColors.skyDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            color: Colors.white,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage Optimizer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Badi aur duplicate files saaf karein',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelRow extends StatelessWidget {
  const _SelRow({
    required this.item,
    required this.selected,
    required this.subtitle,
    required this.onTap,
    required this.onOpen,
    this.flat = false,
  });

  final FileItem item;
  final bool selected;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final bool flat; // true => group card ke andar (bina apne card ke)

  @override
  Widget build(BuildContext context) {
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      margin: flat ? const EdgeInsets.symmetric(vertical: 2) : const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.skySoft : (flat ? AppColors.bg : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.sky : Colors.transparent,
          width: 1.5,
        ),
        boxShadow: flat
            ? null
            : const [
                BoxShadow(
                  color: Color(0x141E88E5),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: selected
                      ? Container(
                          key: const ValueKey('c'),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.skyDark,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        )
                      : FileIconBox(item, key: const ValueKey('i'), size: 42),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kholein',
                  onPressed: onOpen,
                  color: AppColors.skyDark,
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return row;
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.skySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 42, color: AppColors.skyDark),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
