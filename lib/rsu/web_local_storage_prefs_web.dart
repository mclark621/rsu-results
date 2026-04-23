import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:rsu_results/rsu/prefs_storage.dart';

class WebLocalStoragePrefs implements PrefsStorage {
  final web.Storage? _storage;

  WebLocalStoragePrefs() : _storage = web.window.localStorage;

  @override
  String? getString(String key) {
    try {
      return _storage?.getItem(key);
    } catch (e) {
      debugPrint('localStorage getString failed for "$key": $e');
      return null;
    }
  }

  @override
  int? getInt(String key) {
    final raw = getString(key);
    if (raw == null) return null;
    return int.tryParse(raw);
  }

  @override
  Future<void> setString(String key, String value) async {
    try {
      _storage?.setItem(key, value);
    } catch (e) {
      debugPrint('localStorage setString failed for "$key": $e');
    }
  }

  @override
  Future<void> setInt(String key, int value) => setString(key, value.toString());

  @override
  Future<void> remove(String key) async {
    try {
      _storage?.removeItem(key);
    } catch (e) {
      debugPrint('localStorage remove failed for "$key": $e');
    }
  }
}
