import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/centered_surface_panel.dart';
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

  bool _showTimerSecret = false;

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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final app = context.read<RsuAppState>();
      final timerKey = await app.getTimerApiKey();
      final timerSecret = await app.getTimerApiSecret();
      if (!mounted) return;
      setState(() {
        _timerApiKey.text = timerKey ?? '';
        _timerApiSecret.text = timerSecret ?? '';
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('GlobalOAuthSettingsPage load failed: $e\n$st');
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

    setState(() => _saving = true);
    try {
      await app.setTimerApiKeyFromSettings(timerApiKey.isEmpty ? null : timerApiKey);
      await app.setTimerApiSecretFromSettings(timerApiSecret.trim().isEmpty ? null : timerApiSecret);

      await app.syncTimerAccountToFirestore(throwOnFailure: true);

      final reloadedTimerKey = await app.getTimerApiKey();
      final reloadedTimerSecret = await app.getTimerApiSecret();
      if (!mounted) return;
      setState(() {
        _timerApiKey.text = reloadedTimerKey ?? '';
        _timerApiSecret.text = reloadedTimerSecret ?? '';
      });

      CopyableSnackBar.show(context, 'Saved (and synced to server)');
    } catch (e, st) {
      debugPrint('GlobalOAuthSettingsPage save failed: $e\n$st');
      if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Settings'),
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back, color: cs.primary)),
        actions: const [LogoutActionButton()],
      ),
      body: CenteredSurfacePanel(
        maxWidth: 720,
        padding: AppSpacing.paddingLg,
        child: _loading
            ? const LinearProgressIndicator(minHeight: 2)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key_outlined, color: cs.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text('Timer API credentials', style: Theme.of(context).textTheme.titleLarge)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'client_id / redirect_uri / scope are loaded automatically from Firestore (public_config/rsu).\nTimer API credentials are stored per-user in Firestore and synced across devices.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: _timerApiKey,
                    decoration: InputDecoration(
                      labelText: 'rsu_api_key',
                      helperText: 'Sent as a query parameter (rsu_api_key).',
                      suffixIcon: IconButton(
                        tooltip: 'Copy',
                        onPressed: () => _copy('rsu_api_key', _timerApiKey.text),
                        icon: Icon(Icons.copy_outlined, color: cs.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _timerApiSecret,
                    decoration: InputDecoration(
                      labelText: 'X-RSU-API-SECRET',
                      helperText: 'Sent as an HTTP header (X-RSU-API-SECRET).',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Copy',
                            onPressed: () => _copy('X-RSU-API-SECRET', _timerApiSecret.text),
                            icon: Icon(Icons.copy_outlined, color: cs.primary),
                          ),
                          IconButton(
                            tooltip: _showTimerSecret ? 'Hide' : 'Show',
                            onPressed: () => setState(() => _showTimerSecret = !_showTimerSecret),
                            icon: Icon(
                              _showTimerSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    obscureText: !_showTimerSecret,
                    enableSuggestions: false,
                    autocorrect: false,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: Icon(Icons.save_outlined, color: cs.onPrimary),
                    label: Text(_saving ? 'Saving…' : 'Save', style: TextStyle(color: cs.onPrimary)),
                  ),
                ],
              ),
      ),
    );
  }
}
