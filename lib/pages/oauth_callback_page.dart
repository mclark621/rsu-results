import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/rsu_api.dart';
import 'package:rsu_results/rsu/rsu_oauth_service.dart';
import 'package:rsu_results/rsu/web_frame_utils.dart';
import 'package:rsu_results/rsu/rsu_firebase_auth_service.dart';

class OAuthCallbackPage extends StatefulWidget {
  final String code;
  final String returnedState;

  const OAuthCallbackPage({super.key, required this.code, required this.returnedState});

  @override
  State<OAuthCallbackPage> createState() => _OAuthCallbackPageState();
}

class _OAuthCallbackPageState extends State<OAuthCallbackPage> {
  bool _done = false;
  String? _error;
  String? _firebaseAuthError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    _done = true;
    _finish();
  }

  Future<void> _finish() async {
    // Best-effort: remove `?code=...&state=...` from the top-level URL so refreshes don’t
    // re-trigger routing. (We keep the hash route so the app still works with hash routing.)
    WebFrameUtils.clearTopLevelQueryPreserveHash();

    final appState = context.read<RsuAppState>();
    try {
      final tx = await appState.readPkceTransaction();
      if (tx == null) throw Exception('Missing PKCE transaction (state/verifier). Start login again.');
      if (widget.returnedState != tx.state) throw Exception('Bad state parameter.');

      final oauth = RsuOAuthService();
      final clientId = await appState.getClientId();
      final redirectUri = await appState.getRedirectUri();
      debugPrint('OAuth callback: exchanging code (server-side via Firebase). client_id="$clientId" redirect_uri="$redirectUri" returnedState="${widget.returnedState}"');

      final token = await oauth.exchangeCodeForToken(clientId: clientId, redirectUri: redirectUri, codeVerifier: tx.verifier, code: widget.code);

      debugPrint('OAuth callback: token received. expires_in=${token.expiresIn} refresh_token_empty=${token.refreshToken.isEmpty}');
      await appState.saveToken(accessToken: token.accessToken, expiresInSeconds: token.expiresIn, refreshToken: token.refreshToken);
      await appState.clearPkceTransaction();

      // Double-check we can read the token back from storage (important on web).
      await appState.refreshAccessToken();
      debugPrint('OAuth callback: token persisted=${appState.accessToken != null}');

      // Fetch basic RSU identity so we can store per-timer account data in Firestore.
      try {
        final api = RsuApi();
        final me = await api.getCurrentUser(accessToken: token.accessToken, timerApiSecret: appState.timerApiSecret);
        await appState.setRsuIdentity(rsuUserId: me.userId, email: me.email, firstName: me.firstName, lastName: me.lastName);
        debugPrint('OAuth callback: rsu user_id=${me.userId} email=${me.email}');
      } catch (e) {
        debugPrint('OAuth callback: failed to load /Rest/user identity (continuing): $e');
      }

      // Option 2A: mint a Firebase Custom Token based on the RSU OAuth session and sign in.
      // This gives us a stable Firebase uid (`rsu:<user_id>`) for Firestore security rules and per-user data.
      try {
        final firebaseAuth = RsuFirebaseAuthService();
        await firebaseAuth.signInWithRsuAccessToken(rsuAccessToken: token.accessToken);
        debugPrint('OAuth callback: Firebase sign-in ok (custom token).');
        if (mounted) setState(() => _firebaseAuthError = null);
      } catch (e) {
        debugPrint('OAuth callback: Firebase sign-in failed: $e');
        if (mounted) setState(() => _firebaseAuthError = '$e');
      }

      if (!mounted) return;
      // If Firebase sign-in failed, keep the user on this screen so they can copy the error.
      if (_firebaseAuthError != null && _firebaseAuthError!.trim().isNotEmpty) return;
      context.go(AppRoutes.dates);
    } catch (e) {
      debugPrint('OAuth callback failed: $e');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(_error == null ? Icons.check_circle_outline : Icons.error_outline, color: _error == null ? cs.primary : cs.error),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_error == null ? 'Signing you in…' : 'Sign-in failed', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_error != null) ...[
                      CopyableErrorPanel(message: _error!, title: 'OAuth callback failed'),
                      const SizedBox(height: 12),
                    ] else if (_firebaseAuthError != null) ...[
                      CopyableErrorPanel(message: _firebaseAuthError!, title: 'Firebase sign-in failed'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => context.go(AppRoutes.dates),
                        icon: Icon(Icons.arrow_forward, color: cs.onPrimary),
                        label: Text('Continue without Firebase', style: TextStyle(color: cs.onPrimary)),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('Finishing sign-in…', style: Theme.of(context).textTheme.bodySmall),
                    ],
                    Text('You can close the browser tab if one is open.', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
