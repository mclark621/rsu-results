import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';
import 'rsu_public_config_service.dart';
import 'rsu_settings_store.dart';
import 'timer_account_service.dart';

class RsuAppState extends ChangeNotifier {
  final RsuSettingsStore _store;
  final RsuTimerAccountService _timerAccountService;
  final RsuPublicConfigService _publicConfigService;

  RsuAppState({RsuSettingsStore? store, RsuTimerAccountService? timerAccountService, RsuPublicConfigService? publicConfigService})
    : _store = store ?? RsuSettingsStore(),
      _timerAccountService = timerAccountService ?? RsuTimerAccountService(),
      _publicConfigService = publicConfigService ?? RsuPublicConfigService();

  bool _isBootstrapped = false;
  bool get isBootstrapped => _isBootstrapped;

  String? _accessToken;
  String? get accessToken => _accessToken;

  bool _publicConfigLoaded = false;

  String? _publicClientId;
  String? _publicRedirectUri;
  String? _publicScope;
  String? _publicConfigLoadError;
  String? get publicConfigLoadError => _publicConfigLoadError;

  DateTimeRange? _dateRange;
  DateTimeRange? get dateRange => _dateRange;

  int _timeoutSeconds = 20;
  int get timeoutSeconds => _timeoutSeconds;

  String? _timerApiKey;
  String? get timerApiKey => _timerApiKey;

  String? _timerApiSecret;
  String? get timerApiSecret => _timerApiSecret;

  String? _rsuUserId;
  String? get rsuUserId => _rsuUserId;

  ({String email, String firstName, String lastName})? _rsuIdentity;
  ({String email, String firstName, String lastName})? get rsuIdentity => _rsuIdentity;

  String? _raceId;
  String? get raceId => _raceId;

  Color? _pageBackgroundColor;
  Color? get pageBackgroundColor => _pageBackgroundColor;

  Future<void> bootstrap() async {
    if (_isBootstrapped) return;
    try {
      _accessToken = await _store.getAccessToken();
      _dateRange = await _store.getDateRange();
      _timeoutSeconds = await _store.getTimeoutSeconds();
      _timerApiKey = await _store.getTimerApiKey();
      _timerApiSecret = await _store.getTimerApiSecret();
      _rsuUserId = await _store.getRsuUserId();
      _rsuIdentity = await _store.getRsuIdentityDetails();
      _raceId = await _store.getRaceId();
      final bgArgb = await _store.getPageBackgroundArgb();
      _pageBackgroundColor = bgArgb == null ? null : Color(bgArgb);

      await _loadPublicConfig(force: true);

      await _hydrateTimerCredentialsFromFirestoreIfMissing();
    } catch (e) {
      debugPrint('Bootstrap failed: $e');
    } finally {
      _isBootstrapped = true;
      notifyListeners();
    }
  }

  Future<void> _loadPublicConfig({required bool force}) async {
    if (!force && _publicConfigLoaded) return;
    try {
      final publicCfg = await _publicConfigService.fetchOnce();
      _publicClientId = publicCfg?.oauthClientId;
      _publicRedirectUri = publicCfg?.oauthRedirectUri;
      _publicScope = publicCfg?.oauthScope;
      _publicConfigLoadError = null;
      _publicConfigLoaded = true;
    } catch (e) {
      _publicConfigLoadError = e.toString();
      _publicConfigLoaded = true;
      debugPrint('Failed to load public_config/rsu: $e');
    }
  }

  Future<void> reloadPublicConfig() async {
    await _loadPublicConfig(force: true);
    notifyListeners();
  }

  Future<void> _hydrateTimerCredentialsFromFirestoreIfMissing() async {
    final userId = (_rsuUserId ?? '').trim();
    if (userId.isEmpty) return;

    final hasLocalKey = (_timerApiKey ?? '').trim().isNotEmpty;
    final hasLocalSecret = (_timerApiSecret ?? '').trim().isNotEmpty;
    if (hasLocalKey && hasLocalSecret) return;

    if (FirebaseAuth.instance.currentUser == null) return;

    try {
      final acct = await _timerAccountService.getAccount(userId);
      if (acct == null) return;

      final key = acct.timerApiKey.trim();
      final secret = acct.timerApiSecret;
      if (key.isEmpty || secret.trim().isEmpty) return;

      await _store.setTimerApiKey(key);
      await _store.setTimerApiSecret(secret);

      _timerApiKey = key;
      _timerApiSecret = secret;
    } catch (e) {
      debugPrint('Hydrate timer credentials from Firestore failed (ignored): $e');
    }
  }

  Future<void> hydrateTimerCredentialsFromFirestoreIfMissing() async {
    final beforeKey = _timerApiKey;
    final beforeSecret = _timerApiSecret;
    await _hydrateTimerCredentialsFromFirestoreIfMissing();
    if (beforeKey != _timerApiKey || beforeSecret != _timerApiSecret) notifyListeners();
  }

  Future<void> refreshAccessToken() async {
    try {
      final fresh = await _store.getAccessToken();
      if (fresh != _accessToken) {
        _accessToken = fresh;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('refreshAccessToken failed: $e');
    }
  }

  Future<void> refreshCredentialsFromStore() async {
    try {
      final nextTimerKey = await _store.getTimerApiKey();
      final nextTimerSecret = await _store.getTimerApiSecret();

      final changed = nextTimerKey != _timerApiKey || nextTimerSecret != _timerApiSecret;
      _timerApiKey = nextTimerKey;
      _timerApiSecret = nextTimerSecret;
      if (changed) notifyListeners();
    } catch (e) {
      debugPrint('refreshCredentialsFromStore failed (ignored): $e');
    }
  }

  Future<void> saveToken({required String accessToken, required int expiresInSeconds, required String refreshToken}) async {
    await _store.saveToken(accessToken: accessToken, expiresInSeconds: expiresInSeconds, refreshToken: refreshToken);
    _accessToken = accessToken;
    notifyListeners();
  }

  Future<void> setRsuIdentity({required String rsuUserId, required String email, required String firstName, required String lastName}) async {
    await _store.setRsuIdentity(rsuUserId: rsuUserId, email: email, firstName: firstName, lastName: lastName);
    _rsuUserId = rsuUserId;
    _rsuIdentity = (email: email, firstName: firstName, lastName: lastName);

    await _hydrateTimerCredentialsFromFirestoreIfMissing();

    notifyListeners();
    await _upsertTimerAccountIfPossible();
  }

  Future<void> _upsertTimerAccountIfPossible() async {
    final userId = (_rsuUserId ?? '').trim();
    final ident = _rsuIdentity;
    if (userId.isEmpty || ident == null) return;

    final key = (_timerApiKey ?? '').trim();
    final secret = (_timerApiSecret ?? '').trim();

    if (key.isEmpty || secret.isEmpty) return;

    try {
      await _timerAccountService.upsertAccount(
        rsuUserId: userId,
        email: ident.email,
        firstName: ident.firstName,
        lastName: ident.lastName,
        timerApiKey: key,
        timerApiSecret: secret,
      );
    } catch (e) {
      debugPrint('Firestore timer account upsert failed (ignored): $e');
    }
  }

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('FirebaseAuth.signOut failed (ignored): $e');
    }
    await _store.clearToken();
    await _store.clearRsuIdentity();
    _accessToken = null;
    _rsuUserId = null;
    _rsuIdentity = null;
    notifyListeners();
  }

  Future<void> setDateRange(DateTimeRange range) async {
    await _store.setDateRange(range);
    _dateRange = range;
    notifyListeners();
  }

  Future<void> setTimeoutSeconds(int value) async {
    await _store.setTimeoutSeconds(value);
    _timeoutSeconds = value;
    notifyListeners();
  }

  Future<void> setTimerApiKey(String? value) async {
    await _store.setTimerApiKey(value);
    _timerApiKey = (value ?? '').trim().isEmpty ? null : value!.trim();
    notifyListeners();
    await _upsertTimerAccountIfPossible();
  }

  Future<void> setTimerApiSecret(String? value) async {
    await _store.setTimerApiSecret(value);
    _timerApiSecret = (value ?? '').trim().isEmpty ? null : value;
    notifyListeners();
    await _upsertTimerAccountIfPossible();
  }

  Future<void> setRaceId(String value) async {
    await _store.setRaceId(value);
    _raceId = value;
    notifyListeners();
  }

  Future<void> setPageBackgroundColor(Color? color) async {
    await _store.setPageBackgroundArgb(color?.value);
    _pageBackgroundColor = color;
    notifyListeners();
  }

  Future<RsuRaceThemeSettings> getRaceTheme(String raceId) => _store.getRaceTheme(raceId);
  Future<void> setRaceTheme(RsuRaceThemeSettings settings) async {
    await _store.setRaceTheme(settings);
    notifyListeners();
  }

  Future<String> getClientId() async {
    if (!_publicConfigLoaded) await _loadPublicConfig(force: false);
    final v = (_publicClientId ?? '').trim();
    if (v.isEmpty) {
      final loadErr = (_publicConfigLoadError ?? '').trim();
      if (loadErr.isNotEmpty) {
        throw StateError('Failed to read Firestore doc public_config/rsu (so client_id could not be loaded). Underlying error: $loadErr');
      }
      throw StateError('Missing shared RunSignup OAuth client_id. Create Firestore doc public_config/rsu with field oauth_client_id (preferred) or client_id.');
    }
    return v;
  }

  Future<String> getRedirectUri() async {
    if (!_publicConfigLoaded) await _loadPublicConfig(force: false);
    final v = (_publicRedirectUri ?? '').trim();
    if (v.isEmpty) {
      final loadErr = (_publicConfigLoadError ?? '').trim();
      if (loadErr.isNotEmpty) {
        throw StateError('Failed to read Firestore doc public_config/rsu (so redirect_uri could not be loaded). Underlying error: $loadErr');
      }
      throw StateError('Missing shared RunSignup OAuth redirect_uri. Create Firestore doc public_config/rsu with field oauth_redirect_uri (preferred) or redirect_uri.');
    }
    return v;
  }

  String getEffectiveScope() => (_publicScope ?? '').trim().isEmpty ? 'rsu_api_read' : _publicScope!.trim();

  Future<String> getClientSecret() => _store.getClientSecret();
  Future<void> setClientSecret(String v) async {
    await _store.setClientSecret(v);
    notifyListeners();
  }

  Future<String?> getTimerApiKey() => _store.getTimerApiKey();
  Future<void> setTimerApiKeyFromSettings(String? v) async {
    await setTimerApiKey(v);
  }

  Future<String?> getTimerApiSecret() => _store.getTimerApiSecret();
  Future<void> setTimerApiSecretFromSettings(String? v) async {
    await setTimerApiSecret(v);
  }

  Future<void> savePkceTransaction({required String state, required String verifier}) => _store.savePkceTransaction(state: state, verifier: verifier);
  Future<({String state, String verifier})?> readPkceTransaction() => _store.readPkceTransaction();
  Future<void> clearPkceTransaction() => _store.clearPkceTransaction();
}
