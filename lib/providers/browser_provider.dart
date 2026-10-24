import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';
import '../services/archive_service.dart';
import '../services/file_service.dart';
import '../services/optimizer_service.dart';
import '../services/storage_info.dart';
import '../services/transfer_service.dart';
import 'settings_provider.dart';

enum SortMode { name, newest, largest }

extension SortModeX on SortMode {
  String get label => switch (this) {
        SortMode.name => 'Naam (A–Z)',
        SortMode.newest => 'Naya pehle',
        SortMode.largest => 'Badi files pehle',
      };
}

class BrowserState {
  const BrowserState({
    required this.path,
    this.items = const [],
    this.category = FileCategory.all,
    this.query = '',
    this.selected = const {},
    this.sort = SortMode.name,
    this.loading = true,
    this.error,
    this.needsPermission = false,
    this.moveBasket = const [],
    this.showHidden = false,
    this.favoritesOnly = false,
  });

  final String path;
  final List<FileItem> items;
  final FileCategory category;
  final String query;
  final Set<String> selected;
  final SortMode sort;
  final bool loading;
  final String? error;
  final bool needsPermission;
  final List<String> moveBasket;
  final bool showHidden;

  /// true => sirf ⭐ Important files dikh rahi hain
  final bool favoritesOnly;

  bool get isFiltering =>
      favoritesOnly ||
      category != FileCategory.all || query.trim().isNotEmpty;
  bool get selecting => selected.isNotEmpty;
  bool get moving => moveBasket.isNotEmpty;

  BrowserState copyWith({
    String? path,
    List<FileItem>? items,
    FileCategory? category,
    String? query,
    Set<String>? selected,
    SortMode? sort,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? needsPermission,
    List<String>? moveBasket,
    bool? showHidden,
    bool? favoritesOnly,
  }) {
    return BrowserState(
      path: path ?? this.path,
      items: items ?? this.items,
      category: category ?? this.category,
      query: query ?? this.query,
      selected: selected ?? this.selected,
      sort: sort ?? this.sort,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      needsPermission: needsPermission ?? this.needsPermission,
      moveBasket: moveBasket ?? this.moveBasket,
      showHidden: showHidden ?? this.showHidden,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }
}

final fileServiceProvider = Provider<FileService>((ref) => FileService());

final archiveServiceProvider = Provider<ArchiveService>(
  (ref) => ArchiveService(ref.read(fileServiceProvider)),
);

final optimizerServiceProvider = Provider<OptimizerService>((ref) {
  final s = OptimizerService(ref.read(fileServiceProvider));
  ref.onDispose(s.cancel);
  return s;
});

/// Storage ka total / khali. Delete / extract / trash saaf ke baad invalidate hota hai.
final storageStatsProvider = FutureProvider<StorageStats?>(
  (ref) => StorageInfo.read(ref.read(fileServiceProvider).root.path),
);

final transferProvider = ChangeNotifierProvider<TransferService>(
  (ref) => TransferService(ref.read(fileServiceProvider)),
);

final browserProvider = StateNotifierProvider<BrowserNotifier, BrowserState>(
  (ref) => BrowserNotifier(
    ref.read(fileServiceProvider),
    ref.read(archiveServiceProvider),
    ref.read(settingsProvider.notifier),
    ref.read(settingsProvider).showHidden,
  ),
);

class BrowserNotifier extends StateNotifier<BrowserState> {
  BrowserNotifier(
    this._fs,
    this._archive,
    this._settings,
    bool showHidden,
  ) : super(BrowserState(path: _fs.root.path, showHidden: showHidden)) {
    init();
  }

  final FileService _fs;
  final ArchiveService _archive;
  final SettingsNotifier _settings;
  Timer? _debounce;
  int _token = 0; // purane (stale) results ko ignore karne ke liye

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ---------- loading ----------

  Future<void> init() async {
    state = state.copyWith(loading: true, needsPermission: false);
    final ok = await _fs.ensurePermission();
    if (!mounted) return;
    if (!ok) {
      state = state.copyWith(loading: false, needsPermission: true);
      return;
    }
    await open(_fs.root.path);
  }

  Future<void> open(String path) async {
    state = state.copyWith(
      path: path,
      category: FileCategory.all,
      query: '',
      sort: SortMode.name,
      selected: {},
      favoritesOnly: false,
    );
    await _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    final t = ++_token;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = state.favoritesOnly
          ? await _fs.statPaths(_settings.favorites)
          : state.isFiltering
          ? await _fs.search(
              _fs.root.path,
              query: state.query,
              category: state.category,
              showHidden: state.showHidden,
            )
          : await _fs.list(state.path, showHidden: state.showHidden);
      if (!mounted || t != _token) return;
      final paths = items.map((e) => e.path).toSet();
      state = state.copyWith(
        items: _sorted(items, state.sort),
        loading: false,
        selected: state.selected.where(paths.contains).toSet(),
      );
    } catch (_) {
      if (!mounted || t != _token) return;
      state = state.copyWith(
        items: [],
        loading: false,
        error: 'Ye folder khul nahi saka',
      );
    }
  }

  List<FileItem> _sorted(List<FileItem> list, SortMode mode) {
    final l = [...list];
    l.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      switch (mode) {
        case SortMode.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortMode.newest:
          return b.modified.compareTo(a.modified);
        case SortMode.largest:
          return b.size.compareTo(a.size);
      }
    });
    return l;
  }

  // ---------- navigation / filters ----------

  void back() {
    if (state.selecting) {
      clearSelection();
    } else if (state.isFiltering) {
      clearFilters();
    } else if (state.path != _fs.root.path) {
      open(p.dirname(state.path));
    } else if (state.moving) {
      cancelMove();
    }
  }

  void setCategory(FileCategory c) {
    final next = state.category == c ? FileCategory.all : c;
    state = state.copyWith(
      category: next,
      // category chunte hi badi files pehle: safai ke liye best
      sort: next == FileCategory.all ? SortMode.name : SortMode.largest,
      selected: {},
      favoritesOnly: false,
    );
    _load();
  }

  void setQuery(String q) {
    state = state.copyWith(query: q, selected: {}, favoritesOnly: false);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  void clearFilters() {
    state = state.copyWith(
      category: FileCategory.all,
      query: '',
      sort: SortMode.name,
      selected: {},
      favoritesOnly: false,
    );
    _load();
  }

  /// ⭐ Favorites list kholna / band karna
  void toggleFavoritesView() {
    final on = !state.favoritesOnly;
    state = state.copyWith(
      favoritesOnly: on,
      category: FileCategory.all,
      query: '',
      sort: SortMode.name,
      selected: {},
    );
    _load();
  }

  /// Items ko ⭐ Important mark karo (agar sab pehle se marked hon to hata do).
  /// true wapas deta hai agar mark hua, false agar hata.
  bool toggleFavorites(List<FileItem> items) {
    final favs = _settings.favorites;
    final add = !items.every((i) => favs.contains(i.path));
    _settings.setFavorites(items.map((i) => i.path), add: add);
    if (state.favoritesOnly) _load();
    return add;
  }

  /// Hidden files (jo '.' se shuru hon) dikhane / chhupane ka toggle
  void toggleHidden() {
    final next = !state.showHidden;
    _settings.setShowHidden(next);
    state = state.copyWith(showHidden: next);
    _load();
  }

  void setSort(SortMode m) {
    state = state.copyWith(sort: m, items: _sorted(state.items, m));
  }

  // ---------- selection ----------

  void toggle(String path) {
    final s = {...state.selected};
    if (!s.remove(path)) s.add(path);
    state = state.copyWith(selected: s);
  }

  void selectAll() {
    state = state.copyWith(selected: state.items.map((e) => e.path).toSet());
  }

  void clearSelection() => state = state.copyWith(selected: {});

  // ---------- actions ----------

  /// Error message wapas deta hai (null = sab theek).
  Future<String?> rename(FileItem item, String newName) async {
    try {
      await _fs.rename(item.path, newName);
      _settings.remapFavorite(
        item.path,
        p.join(p.dirname(item.path), newName.trim()),
      );
      await _load();
      return null;
    } on FileOpException catch (e) {
      return e.message;
    } catch (_) {
      return 'Rename nahi ho saka (file kisi aur app mein khuli ho sakti hai)';
    }
  }

  Future<BatchResult> batchRename(
    List<FileItem> items,
    BatchOptions options,
  ) async {
    final r = await _fs.batchRename(items, options);
    if (mounted) {
      state = state.copyWith(selected: {});
      await _load();
    }
    return r;
  }

  /// Foran list se hata deta hai (fast feel), phir Trash mein bhejta hai.
  Future<List<TrashRecord>> trash(List<FileItem> items) async {
    final gone = items.map((e) => e.path).toSet();
    state = state.copyWith(
      items: state.items.where((i) => !gone.contains(i.path)).toList(),
      selected: state.selected.difference(gone),
    );
    final out = <TrashRecord>[];
    for (final it in items) {
      try {
        out.add(await _fs.trash(it.path));
      } catch (_) {}
    }
    if (out.length != items.length && mounted) await _load();
    return out;
  }

  Future<void> undo(List<TrashRecord> records) async {
    for (final r in records) {
      try {
        await _fs.restore(r);
      } catch (_) {}
    }
    if (mounted) await _load();
  }

  Future<String?> createFolder(String name) async {
    try {
      await _fs.createFolder(state.path, name);
      await _load();
      return null;
    } on FileOpException catch (e) {
      return e.message;
    } catch (_) {
      return 'Folder nahi ban saka';
    }
  }

  Future<int> emptyTrash() => _fs.emptyTrash();

  /// Trash ki items hamesha ke liye delete (Undo ka waqt khatam hone ke baad)
  Future<void> purge(List<TrashRecord> records) async {
    for (final r in records) {
      try {
        await _fs.purge(r);
      } catch (_) {}
    }
  }

  // ---------- archive extract ----------

  Future<ExtractResult> extractArchive(
    FileItem item, {
    void Function(int done, int total)? onProgress,
  }) async {
    try {
      return await _archive.extract(item.path, onProgress: onProgress);
    } finally {
      if (mounted) await _load();
    }
  }

  // ---------- move ----------

  void startMove() {
    state = state.copyWith(
      moveBasket: state.selected.toList(),
      selected: {},
      category: FileCategory.all,
      query: '',
      favoritesOnly: false,
    );
    _load();
  }

  void cancelMove() => state = state.copyWith(moveBasket: []);

  Future<BatchResult> pasteHere() async {
    final r = await _fs.moveTo(state.moveBasket, state.path);
    for (final src in state.moveBasket) {
      _settings.remapFavorite(src, p.join(state.path, p.basename(src)));
    }
    if (mounted) {
      state = state.copyWith(moveBasket: []);
      await _load();
    }
    return r;
  }
}
