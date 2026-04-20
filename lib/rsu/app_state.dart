import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models.dart';
import 'rsu_firebase_auth_service.dart';
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

  String? _lastTimerCredentialHydrationError;
  String? get lastTimerCredentialHydrationError => _lastTimerCredentialHydrationError;

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

      await _hydrateTimerCredentialsFromFirestore(overwriteLocal: true);
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
      debugPrint('Silent Firebase sign-in failed (ignored): $e');
    }
  }

  Future<void> _hydrateTimerCredentialsFromFirestore({required bool overwriteLocal}) async {
    _lastTimerCredentialHydrationError = null;

    await _ensureFirebaseSessionIfPossible();
    final firebaseUser = FirebaseAuth.instance.currentUser;

    final rsuId = (_rsuUserId ?? '').trim();

    // Prefer canonical lookup by Firebase uid.
    RsuTimerAccount? acct;
    try {
      if (firebaseUser != null) {
        acct = await _timerAccountService.getAccountByFirebaseUid(firebaseUser.uid);
      }

      // Backwards compatibility: older builds keyed the document by rsuUserId.
      if (acct == null && rsuId.isNotEmpty) {
        acct = await _timerAccountService.getAccount(rsuId);
      }
    } catch (e) {
      // This is commonly permission-denied (rules) or unauthenticated.
      _lastTimerCredentialHydrationError = e.toString();
      debugPrint('Hydrate timer credentials: Firestore read failed: $e');

      // If Firestore rules intentionally deny direct client reads (common for secrets),
      // fall back to a privileged Cloud Function read.
      if (firebaseUser != null) {
        try {
          final idToken = (await firebaseUser.getIdToken()) ?? '';
          acct = await _timerAccountService.getAccountByFirebaseUidViaFunction(idToken: idToken);
          if (acct != null) {
            _lastTimerCredentialHydrationError = null;
          }
        } catch (e2) {
          _lastTimerCredentialHydrationError = 'Firestore read failed: $e\nCloud Function fallback also failed: $e2';
          debugPrint('Hydrate timer credentials: function fallback failed: $e2');
          return;
        }
      } else {
        return;
      }
    }

    if (acct == null) return;

    try {
      final key = acct.timerApiKey.trim();
      final secret = acct.timerApiSecret;
      if (key.isEmpty || secret.trim().isEmpty) return;

      final hasLocalKey = (_timerApiKey ?? '').trim().isNotEmpty;
      final hasLocalSecret = (_timerApiSecret ?? '').trim().isNotEmpty;
      final hasLocalBoth = hasLocalKey && hasLocalSecret;

      if (!overwriteLocal && hasLocalBoth) return;

      await _store.setTimerApiKey(key);
      await _store.setTimerApiSecret(secret);
      _timerApiKey = key;
      _timerApiSecret = secret;
    } catch (e) {
      _lastTimerCredentialHydrationError = e.toString();
      debugPrint('Hydrate timer credentials from Firestore failed: $e');
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

  Future<void> ensureFirebaseSignedInOrThrow() async {
    await _ensureFirebaseSessionIfPossible();
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      final hint = (_accessToken ?? '').trim().isEmpty
          ? 'RSU access token is missing/expired.'
          : 'RSU access token exists, but Firebase custom-token sign-in did not complete.';
      throw StateError('No Firebase session. $hint');
    }
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

    debugPrint('Upserting Timer API credentials to Firestore: ${RsuTimerAccountService.collectionPath}/${firebaseUser.uid} (rsuUserId=$rsuId)');
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
      debugPrint('Upserted Timer API credentials to Firestore OK.');
    } catch (e, st) {
      debugPrint('Firestore timer account upsert failed: $e\n$st');
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
