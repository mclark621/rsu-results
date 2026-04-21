import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rsu_results/rsu/web_local_storage.dart';

import 'models.dart';
import 'rsu_config.dart';

abstract class _PrefsLike {
  String? getString(String key);
  int? getInt(String key);

  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);
}

class _SharedPrefsLike implements _PrefsLike {
  final SharedPreferences _prefs;
  _SharedPrefsLike(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

class _WebLocalStoragePrefsLike implements _PrefsLike {
  final WebLocalStorage _storage;

  _WebLocalStoragePrefsLike() : _storage = WebLocalStorage.instance;

  @override
  String? getString(String key) {
    try {
      return _storage.getItem(key);
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
      _storage.setItem(key, value);
    } catch (e) {
      debugPrint('localStorage setString failed for "$key": $e');
    }
  }

  @override
  Future<void> setInt(String key, int value) => setString(key, value.toString());

  @override
  Future<void> remove(String key) async {
    try {
      _storage.removeItem(key);
    } catch (e) {
      debugPrint('localStorage remove failed for "$key": $e');
    }
  }
}

class _MemoryPrefsLike implements _PrefsLike {
  static final Map<String, Object?> _mem = <String, Object?>{};

  @override
  String? getString(String key) {
    final v = _mem[key];
    return v is String ? v : null;
  }

  @override
  int? getInt(String key) {
    final v = _mem[key];
    return v is int ? v : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    _mem[key] = value;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _mem[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _mem.remove(key);
  }
}

class RsuSettingsStore {
  static const _kClientId = 'rsu.clientId';
  static const _kRedirectUri = 'rsu.redirectUri';
  static const _kClientSecret = 'rsu.clientSecret';
  static const _kAccessToken = 'rsu.accessToken';
  static const _kExpiresAtEpochSeconds = 'rsu.expiresAt';
  static const _kRefreshToken = 'rsu.refreshToken';
  static const _kStartDate = 'rsu.startDate';
  static const _kEndDate = 'rsu.endDate';
  static const _kTimeoutSeconds = 'rsu.timeoutSeconds';
  static const _kTimerApiKey = 'rsu.timerApiKey';
  static const _kTimerApiSecret = 'rsu.timerApiSecret';
  static const _kRsuUserId = 'rsu.userId';
  static const _kRsuEmail = 'rsu.email';
  static const _kRsuFirstName = 'rsu.firstName';
  static const _kRsuLastName = 'rsu.lastName';
  static const _kRaceId = 'rsu.raceId';
  static const _kRaceThemePrefix = 'rsu.raceTheme.';
  static const _kPkceState = 'rsu.pkce.state';
  static const _kPkceVerifier = 'rsu.pkce.verifier';
  static const _kPageBackgroundArgb = 'rsu.ui.pageBackgroundArgb';
  static const _kLogoutCode = 'rsu.logoutCode';

  Future<_PrefsLike> _prefs({required bool sensitive}) async {
    if (kIsWeb) return _WebLocalStoragePrefsLike();

    try {
      final p = await SharedPreferences.getInstance();
      // ignore: unused_local_variable
      final _ = p.getString('__rsu_probe__');
      return _SharedPrefsLike(p);
    } catch (e) {
      debugPrint('SharedPreferences unavailable, using in-memory settings store: $e');
      return _MemoryPrefsLike();
    }
  }

  Future<T> _safeRead<T>({required bool sensitive, required T fallback, required T Function(_PrefsLike p) read}) async {
    try {
      final p = await _prefs(sensitive: sensitive);
      return read(p);
    } catch (e) {
      debugPrint('Settings read failed, using fallback: $e');
      return fallback;
    }
  }

  Future<void> _safeWrite({required bool sensitive, required Future<void> Function(_PrefsLike p) write}) async {
    try {
      final p = await _prefs(sensitive: sensitive);
      await write(p);
    } catch (e) {
      debugPrint('Settings write failed (ignored): $e');
    }
  }

  Future<String?> getClientIdOverride() => _safeRead<String?>(sensitive: false, fallback: null, read: (p) {
    final v = (p.getString(_kClientId) ?? '').trim();
    return v.isEmpty ? null : v;
  });

  Future<void> setClientId(String value) => _safeWrite(sensitive: false, write: (p) => p.setString(_kClientId, value.trim()));

  Future<String?> getRedirectUriOverride() => _safeRead<String?>(sensitive: false, fallback: null, read: (p) {
    final v = (p.getString(_kRedirectUri) ?? '').trim();
    return v.isEmpty ? null : v;
  });

  Future<void> setRedirectUri(String value) => _safeWrite(sensitive: false, write: (p) => p.setString(_kRedirectUri, value.trim()));

  Future<String> getClientId() async => (await getClientIdOverride()) ?? RsuConfig.defaultClientId;
  Future<String> getRedirectUri() async => (await getRedirectUriOverride()) ?? RsuConfig.defaultRedirectUri();

  Future<String> getClientSecret() => _safeRead(sensitive: true, fallback: '', read: (p) => p.getString(_kClientSecret) ?? '');

  Future<void> setClientSecret(String value) => _safeWrite(sensitive: true, write: (p) async {
    final v = value.trim();
    if (v.isEmpty) {
      await p.remove(_kClientSecret);
    } else {
      await p.setString(_kClientSecret, v);
    }
  });

  Future<DateTimeRange?> getDateRange() => _safeRead<DateTimeRange?>(
    sensitive: false,
    fallback: null,
    read: (p) {
      final rawStart = (p.getString(_kStartDate) ?? '').trim();
      final rawEnd = (p.getString(_kEndDate) ?? '').trim();
      if (rawStart.isEmpty || rawEnd.isEmpty) return null;

      final start = DateTime.tryParse(rawStart);
      final end = DateTime.tryParse(rawEnd);
      if (start == null || end == null) return null;
      return DateTimeRange(start: start, end: end);
    },
  );

  Future<void> setDateRange(DateTimeRange range) => _safeWrite(
    sensitive: false,
    write: (p) async {
      await p.setString(_kStartDate, _yyyyMmDd(range.start));
      await p.setString(_kEndDate, _yyyyMmDd(range.end));
    },
  );

  Future<void> clearDateRange() => _safeWrite(
    sensitive: false,
    write: (p) async {
      await p.remove(_kStartDate);
      await p.remove(_kEndDate);
    },
  );

  Future<int> getTimeoutSeconds() => _safeRead(sensitive: false, fallback: 20, read: (p) => p.getInt(_kTimeoutSeconds) ?? 20);

  Future<void> setTimeoutSeconds(int value) => _safeWrite(sensitive: false, write: (p) => p.setInt(_kTimeoutSeconds, value));

  // Timer API credentials (v2 API keys)
  // Key is sent as query parameter: rsu_api_key
  Future<String?> getTimerApiKey() => _safeRead<String?>(
    sensitive: true,
    fallback: null,
    read: (p) {
      final v = p.getString(_kTimerApiKey);
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    },
  );

  Future<void> setTimerApiKey(String? value) => _safeWrite(
    sensitive: true,
    write: (p) async {
      final v = (value ?? '').trim();
      if (v.isEmpty) {
        await p.remove(_kTimerApiKey);
      } else {
        await p.setString(_kTimerApiKey, v);
      }
    },
  );

  // Secret is sent as header: X-RSU-API-SECRET
  // WARNING: on web this is stored in localStorage.
  Future<String?> getTimerApiSecret() => _safeRead<String?>(
    sensitive: true,
    fallback: null,
    read: (p) {
      final v = p.getString(_kTimerApiSecret);
      return (v == null || v.isEmpty) ? null : v;
    },
  );

  Future<void> setTimerApiSecret(String? value) => _safeWrite(
    sensitive: true,
    write: (p) async {
      final v = value ?? '';
      if (v.trim().isEmpty) {
        await p.remove(_kTimerApiSecret);
      } else {
        await p.setString(_kTimerApiSecret, v);
      }
    },
  );

  Future<String?> getRaceId() => _safeRead<String?>(
    sensitive: false,
    fallback: null,
    read: (p) {
      final v = p.getString(_kRaceId);
      return (v == null || v.isEmpty) ? null : v;
    },
  );

  Future<void> setRaceId(String raceId) => _safeWrite(sensitive: false, write: (p) => p.setString(_kRaceId, raceId));

  Future<void> clearRaceId() => _safeWrite(
    sensitive: false,
    write: (p) async {
      await p.remove(_kRaceId);
    },
  );

  Future<RsuRaceThemeSettings> getRaceTheme(String raceId) => _safeRead(
    sensitive: false,
    fallback: RsuRaceThemeSettings.defaultsForRace(raceId),
    read: (p) {
      final raw = p.getString('$_kRaceThemePrefix$raceId');
      if (raw == null || raw.isEmpty) return RsuRaceThemeSettings.defaultsForRace(raceId);
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return RsuRaceThemeSettings.fromJson(decoded.cast<String, dynamic>());
      } catch (e) {
        debugPrint('Failed to decode race theme for $raceId: $e');
      }
      return RsuRaceThemeSettings.defaultsForRace(raceId);
    },
  );

  Future<void> setRaceTheme(RsuRaceThemeSettings settings) => _safeWrite(
    sensitive: false,
    write: (p) => p.setString('$_kRaceThemePrefix${settings.raceId}', jsonEncode(settings.toJson())),
  );

  Future<int?> getPageBackgroundArgb() => _safeRead<int?>(sensitive: false, fallback: null, read: (p) => p.getInt(_kPageBackgroundArgb));

  Future<void> setPageBackgroundArgb(int? argb) => _safeWrite(
    sensitive: false,
    write: (p) async {
      if (argb == null) {
        await p.remove(_kPageBackgroundArgb);
      } else {
        await p.setInt(_kPageBackgroundArgb, argb);
      }
    },
  );

  Future<String?> getLogoutCode() => _safeRead<String?>(
    sensitive: true,
    fallback: null,
    read: (p) {
      final v = (p.getString(_kLogoutCode) ?? '').trim();
      return v.isEmpty ? null : v;
    },
  );

  Future<void> setLogoutCode(String value) => _safeWrite(
    sensitive: true,
    write: (p) async {
      final v = value.trim();
      if (v.isEmpty) {
        await p.remove(_kLogoutCode);
      } else {
        await p.setString(_kLogoutCode, v);
      }
    },
  );

  Future<void> clearLogoutCode() => _safeWrite(sensitive: true, write: (p) => p.remove(_kLogoutCode));

  Future<void> saveToken({required String accessToken, required int expiresInSeconds, required String refreshToken}) => _safeWrite(
    sensitive: true,
    write: (p) async {
      await p.setString(_kAccessToken, accessToken);
      if (expiresInSeconds > 0) {
        await p.setInt(_kExpiresAtEpochSeconds, DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch ~/ 1000);
      } else {
        await p.remove(_kExpiresAtEpochSeconds);
      }
      await p.setString(_kRefreshToken, refreshToken);
    },
  );

  Future<void> clearToken() => _safeWrite(
    sensitive: true,
    write: (p) async {
      await p.remove(_kAccessToken);
      await p.remove(_kExpiresAtEpochSeconds);
      await p.remove(_kRefreshToken);
    },
  );

  Future<String?> getRsuUserId() => _safeRead<String?>(
    sensitive: false,
    fallback: null,
    read: (p) {
      final v = p.getString(_kRsuUserId);
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    },
  );

  Future<void> setRsuIdentity({required String rsuUserId, required String email, required String firstName, required String lastName}) => _safeWrite(
    sensitive: false,
    write: (p) async {
      await p.setString(_kRsuUserId, rsuUserId.trim());
      await p.setString(_kRsuEmail, email.trim());
      await p.setString(_kRsuFirstName, firstName.trim());
      await p.setString(_kRsuLastName, lastName.trim());
    },
  );

  Future<void> clearRsuIdentity() => _safeWrite(
    sensitive: false,
    write: (p) async {
      await p.remove(_kRsuUserId);
      await p.remove(_kRsuEmail);
      await p.remove(_kRsuFirstName);
      await p.remove(_kRsuLastName);
    },
  );

  Future<({String email, String firstName, String lastName})?> getRsuIdentityDetails() => _safeRead<({String email, String firstName, String lastName})?>(
    sensitive: false,
    fallback: null,
    read: (p) {
      final email = (p.getString(_kRsuEmail) ?? '').trim();
      final first = (p.getString(_kRsuFirstName) ?? '').trim();
      final last = (p.getString(_kRsuLastName) ?? '').trim();
      if (email.isEmpty && first.isEmpty && last.isEmpty) return null;
      return (email: email, firstName: first, lastName: last);
    },
  );

  Future<String?> getAccessToken() => _safeRead<String?>(
    sensitive: true,
    fallback: null,
    read: (p) {
      final token = p.getString(_kAccessToken);
      if (token == null || token.isEmpty) return null;
      final expiresAt = p.getInt(_kExpiresAtEpochSeconds) ?? 0;
      if (expiresAt != 0 && DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 >= expiresAt) return null;
      return token;
    },
  );

  Future<void> savePkceTransaction({required String state, required String verifier}) => _safeWrite(
    sensitive: true,
    write: (p) async {
      await p.setString(_kPkceState, state);
      await p.setString(_kPkceVerifier, verifier);
    },
  );

  Future<({String state, String verifier})?> readPkceTransaction() => _safeRead<({String state, String verifier})?>(
    sensitive: true,
    fallback: null,
    read: (p) {
      final state = p.getString(_kPkceState) ?? '';
      final verifier = p.getString(_kPkceVerifier) ?? '';
      if (state.isEmpty || verifier.isEmpty) return null;
      return (state: state, verifier: verifier);
    },
  );

  Future<void> clearPkceTransaction() => _safeWrite(
    sensitive: true,
    write: (p) async {
      await p.remove(_kPkceState);
      await p.remove(_kPkceVerifier);
    },
  );

  static String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
