import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// main.dart mein asli SharedPreferences ke sath override hota hai.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider override nahi hua'),
);

class AppSettings {
  const AppSettings({
    this.autoDeleteZip = false,
    this.showHidden = false,
    this.showTime = true,
    this.favorites = const {},
  });

  /// true => extract ke baad original archive khud delete (5 sec Undo ke sath)
  final bool autoDeleteZip;

  /// true => '.' se shuru hone wali hidden files/folders bhi dikhein
  final bool showHidden;

  /// true => size ke saath chhota time bhi dikhe (⋮ menu se band ho sakta hai)
  final bool showTime;

  /// ⭐ Important mark ki hui files/folders ke paths
  final Set<String> favorites;

  AppSettings copyWith({
    bool? autoDeleteZip,
    bool? showHidden,
    bool? showTime,
    Set<String>? favorites,
  }) =>
      AppSettings(
        showTime: showTime ?? this.showTime,
        favorites: favorites ?? this.favorites,
        autoDeleteZip: autoDeleteZip ?? this.autoDeleteZip,
        showHidden: showHidden ?? this.showHidden,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs)
      : super(AppSettings(
          autoDeleteZip: _prefs.getBool(_kAutoZip) ?? false,
          showHidden: _prefs.getBool(_kHidden) ?? false,
          showTime: _prefs.getBool(_kTime) ?? true,
          favorites: (_prefs.getStringList(_kFav) ?? const []).toSet(),
        ));

  static const _kAutoZip = 'auto_delete_zip';
  static const _kHidden = 'show_hidden';
  static const _kTime = 'show_time';
  static const _kFav = 'favorites';

  final SharedPreferences _prefs;

  void setAutoDeleteZip(bool v) {
    state = state.copyWith(autoDeleteZip: v);
    _prefs.setBool(_kAutoZip, v);
  }

  Set<String> get favorites => state.favorites;

  /// add=true => star lagao, false => hatao
  void setFavorites(Iterable<String> paths, {required bool add}) {
    final s = {...state.favorites};
    add ? s.addAll(paths) : s.removeAll(paths);
    state = state.copyWith(favorites: s);
    _prefs.setStringList(_kFav, s.toList());
  }

  /// Rename / move ke baad star naye path par chala jaye
  void remapFavorite(String from, String to) {
    if (!state.favorites.contains(from) || from == to) return;
    final s = {...state.favorites}
      ..remove(from)
      ..add(to);
    state = state.copyWith(favorites: s);
    _prefs.setStringList(_kFav, s.toList());
  }

  void setShowTime(bool v) {
    state = state.copyWith(showTime: v);
    _prefs.setBool(_kTime, v);
  }

  void setShowHidden(bool v) {
    state = state.copyWith(showHidden: v);
    _prefs.setBool(_kHidden, v);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.read(sharedPrefsProvider)),
);
