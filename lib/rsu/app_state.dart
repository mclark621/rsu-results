import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';
import 'rsu_debug_log.dart';
import 'rsu_firebase_auth_service.dart';
import 'rsu_oauth_service.dart';
import 'rsu_public_config_service.dart';
import 'rsu_settings_store.dart';
import 'timer_account.dart';
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

  String? _logoutCode;
  String? get logoutCode => _logoutCode;

  /// RunSignup OAuth token **or** timer `rsu_api_key` + `X-RSU-API-SECRET` (public results) is enough to load races and results.
  bool get canFetchRsuRaceAndResults {
    if ((_accessToken ?? '').trim().isNotEmpty) return true;
    return (_timerApiKey ?? '').trim().isNotEmpty && (_timerApiSecret ?? '').trim().isNotEmpty;
  }

  Color? _pageBackgroundColor;
  Color? get pageBackgroundColor => _pageBackgroundColor;

  Future<void> bootstrap() async {
    if (_isBootstrapped) return;
    try {
      _accessToken = await _store.getAccessToken();
      if (_accessToken == null) {
        await refreshAccessToken();
      }
      _dateRange = await _store.getDateRange();
      _timeoutSeconds = await _store.getTimeoutSeconds();
      _timerApiKey = await _store.getTimerApiKey();
      _timerApiSecret = await _store.getTimerApiSecret();
      _rsuUserId = await _store.getRsuUserId();
      _rsuIdentity = await _store.getRsuIdentityDetails();
      _raceId = await _store.getRaceId();
      _logoutCode = await _store.getLogoutCode();
      final bgArgb = await _store.getPageBackgroundArgb();
      _pageBackgroundColor = bgArgb == null ? null : Color(bgArgb);

      await _loadPublicConfig(force: true);

      await _hydrateTimerCredentialsFromFirestore(overwriteLocal: true);
    } catch (e) {
      rsuDebugLog('Bootstrap failed: $e');
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
      rsuDebugLog('Failed to load public_config/rsu: $e');
    }
  }

  Future<void> reloadPublicConfig() async {
    await _loadPublicConfig(force: true);
    notifyListeners();
  }

  Future<void> _ensureFirebaseSessionIfPossible() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    final token = (_accessToken ?? '').trim();
    if (token.isEmpty) return;
    try {
      final minted = await RsuFirebaseAuthService().signInWithRsuAccessToken(rsuAccessToken: token);

      // Important: rsuUserId/identity should be treated as part of the RunSignup login session.
      // If /Rest/user failed earlier, we can still populate identity from the Cloud Function response.
      final currentUserId = (_rsuUserId ?? '').trim();
      final mintedUserId = minted.rsuUserId.trim();
      if (currentUserId.isEmpty && mintedUserId.isNotEmpty) {
        await setRsuIdentity(rsuUserId: mintedUserId, email: minted.email, firstName: minted.firstName, lastName: minted.lastName);
      }
    } catch (e) {
      rsuDebugLog('Silent Firebase sign-in failed (ignored): $e');
    }
  }

  Future<void> _hydrateTimerCredentialsFromFirestore({required bool overwriteLocal}) async {
    rsuDebugLog('HYDRATE: Starting. overwriteLocal=$overwriteLocal');
    
    await _ensureFirebaseSessionIfPossible();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    rsuDebugLog('HYDRATE: Firebase user = ${firebaseUser?.uid ?? "NULL"}');

    final rsuId = (_rsuUserId ?? '').trim();
    rsuDebugLog('HYDRATE: rsuUserId = ${rsuId.isEmpty ? "EMPTY" : rsuId}');

    // Prefer canonical lookup by Firebase uid.
    RsuTimerAccount? acct;
    if (firebaseUser != null) {
      rsuDebugLog('HYDRATE: Looking up by Firebase UID: ${firebaseUser.uid}');
      acct = await _timerAccountService.getAccountByFirebaseUid(firebaseUser.uid);
      rsuDebugLog('HYDRATE: Lookup by Firebase UID result: ${acct == null ? "NOT FOUND" : "FOUND key=${acct.timerApiKey.isNotEmpty}"}');
    }

    // Backwards compatibility: older builds keyed the document by rsuUserId.
    if (acct == null && rsuId.isNotEmpty) {
      rsuDebugLog('HYDRATE: Looking up by rsuUserId doc ID: $rsuId');
      acct = await _timerAccountService.getAccount(rsuId);
      rsuDebugLog('HYDRATE: Lookup by rsuUserId doc ID result: ${acct == null ? "NOT FOUND" : "FOUND key=${acct.timerApiKey.isNotEmpty}"}');
    }

    // Fallback: query by rsuUserId FIELD (handles auto-generated doc IDs or different naming)
    if (acct == null && rsuId.isNotEmpty) {
      rsuDebugLog('HYDRATE: Looking up by rsuUserId FIELD query: $rsuId');
      acct = await _timerAccountService.getAccountByRsuUserIdField(rsuId, ownerFirebaseUid: firebaseUser?.uid);
      rsuDebugLog('HYDRATE: Lookup by rsuUserId FIELD result: ${acct == null ? "NOT FOUND" : "FOUND key=${acct.timerApiKey.isNotEmpty}"}');
    }

    if (acct == null) {
      rsuDebugLog('HYDRATE: No account found in Firestore after ALL lookups - credentials cannot be hydrated!');
      rsuDebugLog('HYDRATE: Tried paths: rsu_timer_accounts/${firebaseUser?.uid}, rsu_timer_accounts/$rsuId, and query by rsuUserId field');
      return;
    }

    try {
      final key = acct.timerApiKey.trim();
      final secret = acct.timerApiSecret;
      rsuDebugLog('HYDRATE: Account found. key=${key.isEmpty ? "EMPTY" : "SET(${key.length} chars)"} secret=${secret.trim().isEmpty ? "EMPTY" : "SET(${secret.length} chars)"}');
      
      if (key.isEmpty || secret.trim().isEmpty) {
        rsuDebugLog('HYDRATE: Account exists but key/secret are empty - skipping');
        return;
      }

      final hasLocalKey = (_timerApiKey ?? '').trim().isNotEmpty;
      final hasLocalSecret = (_timerApiSecret ?? '').trim().isNotEmpty;
      final hasLocalBoth = hasLocalKey && hasLocalSecret;

      if (!overwriteLocal && hasLocalBoth) {
        rsuDebugLog('HYDRATE: Local credentials already present and overwriteLocal=false - skipping');
        return;
      }

      rsuDebugLog('HYDRATE: Storing credentials to local storage...');
      await _store.setTimerApiKey(key);
      await _store.setTimerApiSecret(secret);
      _timerApiKey = key;
      _timerApiSecret = secret;
      rsuDebugLog('HYDRATE: SUCCESS - credentials stored locally');
    } catch (e) {
      rsuDebugLog('HYDRATE: FAILED to store credentials: $e');
    }
  }

  Future<void> hydrateTimerCredentialsFromFirestore({bool overwriteLocal = true}) async {
    final beforeKey = _timerApiKey;
    final beforeSecret = _timerApiSecret;
    await _hydrateTimerCredentialsFromFirestore(overwriteLocal: overwriteLocal);
    if (beforeKey != _timerApiKey || beforeSecret != _timerApiSecret) notifyListeners();
  }

  Future<void> prepareForApiCall() async {
    // Always hydrate credentials from Firestore (when logged in) right before hitting RSU APIs,
    // so new devices and fresh sessions pull the latest timer creds.
    await refreshAccessToken();
    await hydrateTimerCredentialsFromFirestore(overwriteLocal: true);
  }

  Future<void> refreshAccessToken() async {
    try {
      var fresh = await _store.getAccessToken();
      if (fresh != null) {
        if (fresh != _accessToken) {
          _accessToken = fresh;
          notifyListeners();
        }
        return;
      }

      final rt = await _store.getRefreshToken();
      if (rt == null || rt.trim().isEmpty) return;

      final clientId = await getClientId();
      final oauth = RsuOAuthService();
      final token = await oauth.refreshAccessTokenViaFirebase(clientId: clientId, refreshToken: rt.trim());
      final nextRefresh = token.refreshToken.trim().isNotEmpty ? token.refreshToken.trim() : rt.trim();
      await saveToken(accessToken: token.accessToken, expiresInSeconds: token.expiresIn, refreshToken: nextRefresh);
    } catch (e) {
      rsuDebugLog('refreshAccessToken failed: $e');
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
      rsuDebugLog('refreshCredentialsFromStore failed (ignored): $e');
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

    await _hydrateTimerCredentialsFromFirestore(overwriteLocal: true);

    notifyListeners();
    await _upsertTimerAccountIfPossible(throwOnFailure: false);
  }

  Future<void> _upsertTimerAccountIfPossible({required bool throwOnFailure}) async {
    // IMPORTANT: The canonical Firestore key is Firebase uid (not rsuUserId), because
    // Firebase is the actual security boundary for reads/writes.
    if (FirebaseAuth.instance.currentUser == null) {
      await _ensureFirebaseSessionIfPossible();
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      if (throwOnFailure) {
        final hint = (_accessToken ?? '').trim().isEmpty
            ? 'RSU access token is missing/expired.'
            : 'RSU access token exists, but custom-token sign-in failed (check Cloud Function rsuFirebaseLogin + Firebase Auth settings).';
        throw StateError('Cannot save to Firestore yet: no Firebase session. $hint');
      }
      return;
    }

    final key = (_timerApiKey ?? '').trim();
    final secret = (_timerApiSecret ?? '').trim();

    if (key.isEmpty || secret.isEmpty) {
      if (throwOnFailure) throw StateError('Timer API key/secret are empty — nothing to save to Firestore.');
      return;
    }

    final rsuId = (_rsuUserId ?? '').trim();
    final ident = _rsuIdentity;

    // We must be able to link Timer API credentials to a specific RunSignup user.
    // If rsuUserId is missing, refuse the explicit "sync to server" request.
    if (throwOnFailure && rsuId.isEmpty) {
      throw StateError(
        'Cannot sync Timer API credentials to Firestore yet: missing rsuUserId.\n\n'
        'This usually means the app has a RunSignup access token stored, but identity hydration has not completed.\n'
        'Fix: sign out and sign in again, or ensure rsuFirebaseLogin is working so the app can hydrate rsuUserId.',
      );
    }

    rsuDebugLog('Upserting Timer API credentials to Firestore: ${RsuTimerAccountService.collectionPath}/${firebaseUser.uid} (rsuUserId=$rsuId)');
    try {
      await _timerAccountService.upsertAccount(
        firebaseUid: firebaseUser.uid,
        rsuUserId: rsuId.isEmpty ? null : rsuId,
        email: ident?.email,
        firstName: ident?.firstName,
        lastName: ident?.lastName,
        timerApiKey: key,
        timerApiSecret: secret,
      );
      rsuDebugLog('Upserted Timer API credentials to Firestore OK.');
    } catch (e, st) {
      rsuDebugLog('Firestore timer account upsert failed: $e\n$st');
      if (throwOnFailure) rethrow;
    }
  }

  Future<void> syncTimerAccountToFirestore({bool throwOnFailure = true}) => _upsertTimerAccountIfPossible(throwOnFailure: throwOnFailure);

  Future<bool> canSyncTimerAccountToFirestore() async {
    final key = (_timerApiKey ?? '').trim();
    final secret = (_timerApiSecret ?? '').trim();
    return FirebaseAuth.instance.currentUser != null && key.isNotEmpty && secret.isNotEmpty;
  }

  Future<void> logout() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      rsuDebugLog('FirebaseAuth.signOut failed (ignored): $e');
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
    await _upsertTimerAccountIfPossible(throwOnFailure: false);
  }

  Future<void> setTimerApiSecret(String? value) async {
    await _store.setTimerApiSecret(value);
    _timerApiSecret = (value ?? '').trim().isEmpty ? null : value;
    notifyListeners();
    await _upsertTimerAccountIfPossible(throwOnFailure: false);
  }

  Future<void> setRaceId(String value) async {
    await _store.setRaceId(value);
    _raceId = value;
    notifyListeners();
  }

  Future<void> setLogoutCode(String? code) async {
    await _store.setLogoutCode(code);
    _logoutCode = (code ?? '').trim().isEmpty ? null : code!.trim();
    notifyListeners();
  }

  Future<void> clearLogoutCode() async {
    await _store.clearLogoutCode();
    _logoutCode = null;
    notifyListeners();
  }

  Future<void> setPageBackgroundColor(Color? color) async {
    await _store.setPageBackgroundArgb(color?.toARGB32());
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
