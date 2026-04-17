import 'package:flutter/foundation.dart';

class RsuConfig {
  // RunSignup REST API base (note the api.runsignup.com host and lowercase /rest path).
  static const String endpointBase = 'https://api.runsignup.com/rest/';

  static const String authEndpoint = 'https://runsignup.com/Profile/OAuth2/RequestGrant';
  static const String tokenEndpoint = 'https://runsignup.com/rest/v2/auth/auth-code-redemption.json';

  /// Cloud Function proxy to avoid browser CORS when running on web.
  ///
  /// URL format for HTTPS functions:
  ///   https://<region>-<projectId>.cloudfunctions.net/<functionName>
  ///
  /// This function is created as `rsuProxy` in `functions/src/rsuProxy.ts`.
  static String firebaseFunctionsProxyBase({required String projectId, String region = 'us-central1'}) => 'https://$region-$projectId.cloudfunctions.net/rsuProxy';

  /// Server-side OAuth token exchange.
  ///
  /// This function is created as `rsuTokenExchange` in `functions/src/rsuTokenExchange.ts` and uses
  /// the Cloud Functions secret `RSU_OAUTH_CLIENT_SECRET` so the client never sees the secret.
  static String firebaseFunctionsTokenExchangeUrl({required String projectId, String region = 'us-central1'}) => 'https://$region-$projectId.cloudfunctions.net/rsuTokenExchange';

  // Public OAuth (Option 1) uses PKCE and MUST NOT embed a client secret.
  static const String defaultClientId = '256';
  static const String defaultScope = 'rsu_api_read';

  // Dreamflow preview / published web origin.
  // This should match the Redirect URI configured in RunSignup.
  static const String defaultWebRedirectUri = 'https://q12cobdll470lzsqt67r.share.dreamflow.app';

  /// If you have a RunSignup OAuth app configured for desktop (loopback redirect),
  /// set this in Settings inside the app.
  ///
  /// For web we default to the Dreamflow app origin (site root).
  ///
  /// This avoids “deep link” hosting requirements (some static hosts 404 on
  /// `/oauth/callback` because they don’t rewrite unknown paths to `index.html`).
  ///
  /// The app will internally detect `?code=...&state=...` on `/` and reroute to
  /// the in-app handler.
  static String defaultRedirectUri() {
    if (kIsWeb) {
      return defaultWebRedirectUri;
    }
    return 'http://127.0.0.1:43823/callback';
  }
}
