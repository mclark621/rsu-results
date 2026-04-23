import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/centered_surface_panel.dart';
import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/rsu_api.dart';
import 'package:rsu_results/rsu/rsu_oauth_service.dart';
import 'package:rsu_results/rsu/web_frame_utils.dart';
import 'package:rsu_results/rsu/rsu_firebase_auth_service.dart';
import 'package:rsu_results/theme.dart';

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
    // Best-effort: remove `?code=...&state=...` from the top-level URL so refreshes don't
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
        final minted = await firebaseAuth.signInWithRsuAccessToken(rsuAccessToken: token.accessToken);
        debugPrint('OAuth callback: Firebase sign-in ok (custom token).');

        // If /Rest/user failed above, still persist identity from the minted custom token response.
        if ((appState.rsuUserId ?? '').trim().isEmpty && minted.rsuUserId.trim().isNotEmpty) {
          await appState.setRsuIdentity(rsuUserId: minted.rsuUserId, email: minted.email, firstName: minted.firstName, lastName: minted.lastName);
          debugPrint('OAuth callback: rsu identity hydrated from rsuFirebaseLogin user payload.');
        }

        // NOW that Firebase is signed in, hydrate timer API credentials from Firestore.
        // This is critical: setRsuIdentity was called BEFORE Firebase sign-in, so its internal
        // hydration attempt failed. We must do it again now that we have a Firebase session.
        debugPrint('OAuth callback: BEFORE hydration - key=${appState.timerApiKey} secret=${appState.timerApiSecret != null}');
        debugPrint('OAuth callback: Firebase currentUser.uid = ${FirebaseAuth.instance.currentUser?.uid}');
        await appState.hydrateTimerCredentialsFromFirestore(overwriteLocal: true);
        debugPrint('OAuth callback: AFTER hydration - key=${appState.timerApiKey} secret=${appState.timerApiSecret != null}');

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
      appBar: AppBar(title: const Text('Runsignup Results')),
      body: CenteredSurfacePanel(
        maxWidth: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_error == null ? Icons.check_circle_outline : Icons.error_outline, color: _error == null ? cs.primary : cs.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error == null ? 'Signing you in…' : 'Sign-in failed',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_error != null) ...[
              Text(
                'Something went wrong during the OAuth callback.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 16),
              CopyableErrorPanel(message: _error!, title: 'OAuth callback failed'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.login),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionOrange,
                  foregroundColor: AppColors.onActionOrange,
                  minimumSize: const Size.fromHeight(54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  splashFactory: NoSplash.splashFactory,
                ),
                icon: Icon(Icons.arrow_back, color: AppColors.onActionOrange),
                label: Text(
                  'Try again',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.onActionOrange),
                ),
              ),
            ] else if (_firebaseAuthError != null) ...[
              Text(
                'RSU sign-in succeeded but Firebase sign-in failed.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 16),
              CopyableErrorPanel(message: _firebaseAuthError!, title: 'Firebase sign-in failed'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.dates),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionOrange,
                  foregroundColor: AppColors.onActionOrange,
                  minimumSize: const Size.fromHeight(54),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  splashFactory: NoSplash.splashFactory,
                ),
                icon: Icon(Icons.arrow_forward, color: AppColors.onActionOrange),
                label: Text(
                  'Continue without Firebase',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.onActionOrange),
                ),
              ),
            ] else ...[
              Text(
                'Finishing your sign-in process.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            Text(
              'Tip: you can close the browser tab if one is open.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
