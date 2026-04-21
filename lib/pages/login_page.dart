import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/rsu_config.dart';
import 'package:rsu_results/rsu/rsu_oauth_service.dart';
import 'package:rsu_results/theme.dart';

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

      if (kIsWeb) {
        final currentOrigin = Uri.base.origin;
        final configuredOrigin = Uri.tryParse(effectiveRedirect)?.origin ?? '';
        if (configuredOrigin.isEmpty) throw StateError('Invalid redirect_uri: "$effectiveRedirect"');
        if (configuredOrigin != currentOrigin) {
          throw StateError(
            'This page is running on "$currentOrigin" but Firestore redirect_uri is "$configuredOrigin".\n\n'
            'Open the app at the configured origin (or update public_config/rsu) and try again.',
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

      if (mounted) context.go('${AppRoutes.oauthWaiting}?state=$state');
      await oauth.launchAuthorizationUrl(authUrl);
    } catch (e) {
      debugPrint('OAuth start failed: $e');
      setState(() => _error = '$e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Runsignup Results', textAlign: TextAlign.center, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    CopyableErrorPanel(message: _error!, title: 'Sign-in error'),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.actionOrange,
                        foregroundColor: AppColors.onActionOrange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        splashFactory: NoSplash.splashFactory,
                      ),
                      onPressed: _loading ? null : _startOAuth,
                      icon: const Icon(Icons.login, color: AppColors.onActionOrange, size: 20),
                      label: Text(_loading ? 'Opening…' : 'Sign in with RunSignup', style: const TextStyle(color: AppColors.onActionOrange)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
