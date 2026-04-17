import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';

class OAuthWaitingPage extends StatefulWidget {
  final String state;

  const OAuthWaitingPage({super.key, required this.state});

  @override
  State<OAuthWaitingPage> createState() => _OAuthWaitingPageState();
}

class _OAuthWaitingPageState extends State<OAuthWaitingPage> {
  String? _redirectUri;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      // If OAuth happens in another tab/window, we still want this screen to
      // detect the token once it’s written to localStorage and advance.
      // A lightweight poll avoids wiring more complex cross-tab messaging.
      _startPollingForToken();
    });
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  bool _polling = true;

  void _startPollingForToken() {
    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted || !_polling) return;
      await _checkForToken(navigateIfFound: true, silent: true);
      if (mounted && _polling) _startPollingForToken();
    });
  }

  Future<void> _load() async {
    try {
      final uri = await context.read<RsuAppState>().getRedirectUri();
      if (!mounted) return;
      setState(() => _redirectUri = uri);
    } catch (_) {
      if (!mounted) return;
      setState(() => _redirectUri = null);
    }
  }

  Future<void> _checkForToken({required bool navigateIfFound, required bool silent}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final appState = context.read<RsuAppState>();
      await appState.refreshAccessToken();
      final token = appState.accessToken;
      if (token != null && token.isNotEmpty) {
        if (!mounted) return;
        if (navigateIfFound) {
          context.go(AppRoutes.dates);
        }
      } else {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in yet. Finish approval in the browser tab.')));
        }
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final redirectUri = _redirectUri ?? '${Uri.base.origin}/oauth/callback';

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
                        Icon(Icons.hourglass_bottom, color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Finish sign-in in your browser', style: Theme.of(context).textTheme.titleLarge)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'After you approve access, RunSignup will redirect back to the app to complete sign-in.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _checking ? null : () => _checkForToken(navigateIfFound: true, silent: false),
                      icon: Icon(Icons.refresh, color: cs.onSecondaryContainer),
                      label: Text(_checking ? 'Checking…' : 'I approved in the browser — continue', style: TextStyle(color: cs.onSecondaryContainer)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'If you see an approval/redirect error, it usually means the redirect_uri in RunSignup doesn’t exactly match what the app sent.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text('redirect_uri currently being sent (copy/paste):', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText(redirectUri, style: Theme.of(context).textTheme.bodyMedium)),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: redirectUri));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied redirect_uri to clipboard')));
                                }
                              },
                              child: const Text('Copy'),
                            ),
                          ],
                        ),
                      ),
                    ),
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
