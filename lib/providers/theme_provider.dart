import 'package:flutter/material.dart';
import 'package:rttext/core/accents.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's accent choice and persists it across restarts. The seed
/// color it exposes is fed into the app theme so the whole ColorScheme
/// follows the selected preset.
class ThemeProvider extends ChangeNotifier {
  static const _prefsKey = 'accent_id';

  String _accentId = kDefaultAccentId;

  String get accentId => _accentId;

  /// Seed color for the active accent preset.
  Color get seed => accentById(_accentId).color;

  /// Reads the persisted accent. Called once at startup; falls back to the
  /// default when nothing is stored or prefs are unavailable (e.g. tests).
  Future<void> load() async {
    try {
      final stored = (await SharedPreferences.getInstance())
          .getString(_prefsKey);
      if (stored != null && stored != _accentId) {
        _accentId = accentById(stored).id;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default accent when the store can't be read.
    }
  }

  /// Applies [id] app-wide and remembers it for next launch.
  Future<void> setAccent(String id) async {
    final resolved = accentById(id).id;
    if (resolved == _accentId) return;
    _accentId = resolved;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance())
          .setString(_prefsKey, resolved);
    } catch (_) {
      // The choice still applies for this session if persisting fails.
    }
  }
}
