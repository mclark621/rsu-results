import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/rsu_config.dart';
import 'package:rsu_results/rsu/rsu_oauth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;

  Future<void> _startOAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<RsuAppState>();
      final clientId = await appState.getClientId();
      final redirectUri = await appState.getRedirectUri();

      final oauth = RsuOAuthService();
      final state = RsuOAuthService.randomUrlSafeString(16);
      final verifier = RsuOAuthService.randomUrlSafeString(48);
      final challenge = RsuOAuthService.codeChallengeS256(verifier);

      final effectiveRedirect = redirectUri.trim();
      if (effectiveRedirect.isEmpty) {
        throw StateError('Missing redirect_uri. Configure Firestore doc public_config/rsu (oauth_redirect_uri).');
      }

      // On web, the app origin must match the configured redirect URI origin.
      // If they don’t match, PKCE state (localStorage) won’t line up after redirect.
      if (kIsWeb) {
        final currentOrigin = Uri.base.origin;
        final configuredOrigin = Uri.tryParse(effectiveRedirect)?.origin ?? '';
        if (configuredOrigin.isEmpty) throw StateError('Invalid redirect_uri: "$effectiveRedirect"');
        if (configuredOrigin != currentOrigin) {
          throw StateError(
            'This page is running on "$currentOrigin" but Firestore redirect_uri is "$configuredOrigin".\n\n'
            'Open the app at the configured origin (or update public_config/rsu) and try again.'
          );
        }
      }

      debugPrint('OAuth redirect_uri="$effectiveRedirect" on origin="${Uri.base.origin}"');
      final authUrl = await oauth.buildAuthorizationUrl(
        clientId: clientId,
        redirectUri: effectiveRedirect,
        scope: RsuConfig.defaultScope,
        state: state,
        codeChallenge: challenge,
      );

      await appState.savePkceTransaction(state: state, verifier: verifier);

      if (mounted) {
        context.go('${AppRoutes.oauthWaiting}?state=$state');
      }
      await oauth.launchAuthorizationUrl(authUrl);
    } catch (e) {
      debugPrint('OAuth start failed: $e');
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                        Icon(Icons.lock_outline, color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Connect RunSignup', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Public OAuth (Option 1) with PKCE. No backend, no client secret embedded.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      CopyableErrorPanel(message: _error!, title: 'Sign-in error'),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: _loading ? null : _startOAuth,
                      icon: Icon(Icons.open_in_browser, color: cs.onPrimary),
                      label: Text(_loading ? 'Opening…' : 'Sign in with RunSignup', style: TextStyle(color: cs.onPrimary)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.settingsGlobal),
                      icon: Icon(Icons.settings_outlined, color: cs.primary),
                      label: Text('Global Settings (Timer API)', style: TextStyle(color: cs.primary)),

                    ),
                    const SizedBox(height: 10),
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
