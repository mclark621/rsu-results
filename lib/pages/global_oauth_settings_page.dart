import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/rsu/app_state.dart';

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

      final reloadedTimerKey = await app.getTimerApiKey();
      final reloadedTimerSecret = await app.getTimerApiSecret();
      final reloadedClientSecret = await app.getClientSecret();
      if (!mounted) return;
      setState(() {
        _timerApiKey.text = reloadedTimerKey ?? '';
        _timerApiSecret.text = reloadedTimerSecret ?? '';
        _clientSecret.text = reloadedClientSecret;
      });

      CopyableSnackBar.show(context, 'Saved');
    } catch (e) {
      if (!mounted) return;
      CopyableSnackBar.show(context, 'Failed to save: $e');
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _loading
                    ? const LinearProgressIndicator()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('RunSignup credentials', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Text(
                            'client_id / redirect_uri / scope are loaded automatically from Firestore (public_config/rsu) and are not shown here.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 18),
                          Text('OAuth token exchange (temporary)', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _clientSecret,
                            decoration: InputDecoration(
                              labelText: 'client_secret',
                              helperText: 'Only required for some RunSignup apps. Hidden by default. You can copy this to store in Firebase Secret Manager.',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                            ),
                            obscureText: !_showClientSecret,
                            enableSuggestions: false,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 18),
                          Text('Timer API (v2) credentials', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _timerApiKey,
                            decoration: InputDecoration(
                              labelText: 'rsu_api_key (query parameter)',
                              suffixIcon: IconButton(
                                tooltip: 'Copy',
                                onPressed: () => _copy('rsu_api_key', _timerApiKey.text),
                                icon: const Icon(Icons.copy_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _timerApiSecret,
                            decoration: InputDecoration(
                              labelText: 'X-RSU-API-SECRET (header)',
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
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
                            ),
                            obscureText: !_showTimerSecret,
                            enableSuggestions: false,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'RunSignup requires the key as a GET parameter named rsu_api_key, and the secret as an HTTP header named X-RSU-API-SECRET.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: Icon(Icons.save_outlined, color: cs.onPrimary),
                            label: Text(_saving ? 'Saving…' : 'Save', style: TextStyle(color: cs.onPrimary)),
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
