import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/centered_surface_panel.dart';
import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/theme.dart';

class GlobalOAuthSettingsPage extends StatefulWidget {
  const GlobalOAuthSettingsPage({super.key});

  @override
  State<GlobalOAuthSettingsPage> createState() => _GlobalOAuthSettingsPageState();
}

class _GlobalOAuthSettingsPageState extends State<GlobalOAuthSettingsPage> {
  final _timerApiKey = TextEditingController();
  final _timerApiSecret = TextEditingController();
  final _clientSecret = TextEditingController();

  bool _showTimerSecret = false;
  bool _showClientSecret = false;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _timerApiKey.dispose();
    _timerApiSecret.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final app = context.read<RsuAppState>();
      final timerKey = await app.getTimerApiKey();
      final timerSecret = await app.getTimerApiSecret();
      final clientSecret = await app.getClientSecret();
      if (!mounted) return;
      setState(() {
        _timerApiKey.text = timerKey ?? '';
        _timerApiSecret.text = timerSecret ?? '';
        _clientSecret.text = clientSecret;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CopyableSnackBar.show(context, 'Failed to load settings: $e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = context.read<RsuAppState>();

    final timerApiKey = _timerApiKey.text.trim();
    final timerApiSecret = _timerApiSecret.text;
    final clientSecret = _clientSecret.text;

    setState(() => _saving = true);
    try {
      await app.setTimerApiKeyFromSettings(timerApiKey.isEmpty ? null : timerApiKey);
      await app.setTimerApiSecretFromSettings(timerApiSecret.trim().isEmpty ? null : timerApiSecret);
      await app.setClientSecret(clientSecret);

      // IMPORTANT: Don't silently pretend we saved to the server.
      // If the user is signed in and has an RSU identity, this should create/update the Firestore doc.
      await app.syncTimerAccountToFirestore(throwOnFailure: true);

      final reloadedTimerKey = await app.getTimerApiKey();
      final reloadedTimerSecret = await app.getTimerApiSecret();
      final reloadedClientSecret = await app.getClientSecret();
      if (!mounted) return;
      setState(() {
        _timerApiKey.text = reloadedTimerKey ?? '';
        _timerApiSecret.text = reloadedTimerSecret ?? '';
        _clientSecret.text = reloadedClientSecret;
      });

      CopyableSnackBar.show(context, 'Saved (and synced to server)');
    } catch (e, st) {
      debugPrint('GlobalOAuthSettingsPage save failed: $e\n$st');
      if (!mounted) return;

      // On web, Firestore errors can surface as a generic "converted Future" exception.
      // Still try to unwrap the useful fields when possible.
      if (e is FirebaseException) {
        final msg = [e.code, e.message].where((v) => (v ?? '').trim().isNotEmpty).join(': ');
        CopyableSnackBar.show(context, 'Failed to save: $msg');
      } else {
        CopyableSnackBar.show(context, 'Failed to save: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy(String label, String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      CopyableSnackBar.show(context, 'Nothing to copy');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: v));
      if (!mounted) return;
      CopyableSnackBar.show(context, 'Copied $label');
    } catch (e) {
      if (!mounted) return;
      CopyableSnackBar.show(context, 'Copy failed: $e');
    }
  }

  InputDecoration _fieldDecoration(BuildContext context, {required String label, String? helper, List<Widget>? suffixWidgets}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.6), width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4), width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.primary, width: 2)),
      suffixIcon: suffixWidgets != null ? Row(mainAxisSize: MainAxisSize.min, children: suffixWidgets) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bay City Timing & Events'),
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back, color: cs.primary)),
        actions: const [LogoutActionButton()],
      ),
      body: CenteredSurfacePanel(
        maxWidth: 720,
        child: _loading
            ? const LinearProgressIndicator()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Global Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    'Configure your RunSignup credentials here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
                  ),
                  const SizedBox(height: 16),
                  Text('OAuth token exchange', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'client_id / redirect_uri / scope are loaded automatically from Firestore (public_config/rsu).',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clientSecret,
                    decoration: _fieldDecoration(
                      context,
                      label: 'client_secret',
                      helper: 'Only required for some RunSignup apps.',
                      suffixWidgets: [
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () => _copy('client_secret', _clientSecret.text),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                        IconButton(
                          tooltip: _showClientSecret ? 'Hide' : 'Show',
                          onPressed: () => setState(() => _showClientSecret = !_showClientSecret),
                          icon: Icon(_showClientSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ],
                    ),
                    obscureText: !_showClientSecret,
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 18),
                  Text('Timer API (v2) credentials', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timerApiKey,
                    decoration: _fieldDecoration(
                      context,
                      label: 'rsu_api_key (query parameter)',
                      suffixWidgets: [
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () => _copy('rsu_api_key', _timerApiKey.text),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _timerApiSecret,
                    decoration: _fieldDecoration(
                      context,
                      label: 'X-RSU-API-SECRET (header)',
                      suffixWidgets: [
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () => _copy('X-RSU-API-SECRET', _timerApiSecret.text),
                          icon: const Icon(Icons.copy_outlined),
                        ),
                        IconButton(
                          tooltip: _showTimerSecret ? 'Hide' : 'Show',
                          onPressed: () => setState(() => _showTimerSecret = !_showTimerSecret),
                          icon: Icon(_showTimerSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        ),
                      ],
                    ),
                    obscureText: !_showTimerSecret,
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.actionOrange,
                      foregroundColor: AppColors.onActionOrange,
                      minimumSize: const Size.fromHeight(54),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      splashFactory: NoSplash.splashFactory,
                    ),
                    icon: Icon(Icons.save_outlined, color: AppColors.onActionOrange),
                    label: Text(
                      _saving ? 'Saving…' : 'Save',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.onActionOrange),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tip: RunSignup requires the key as a GET parameter named rsu_api_key, and the secret as an HTTP header named X-RSU-API-SECRET.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
                  ),
                ],
              ),
      ),
    );
  }
}
