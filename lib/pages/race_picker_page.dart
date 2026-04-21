import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:rsu_results/components/centered_surface_panel.dart';
import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/models.dart';
import 'package:rsu_results/rsu/rsu_api.dart';
import 'package:rsu_results/theme.dart';

class RacePickerPage extends StatefulWidget {
  const RacePickerPage({super.key});

  @override
  State<RacePickerPage> createState() => _RacePickerPageState();
}

class _RacePickerPageState extends State<RacePickerPage> {
  bool _loading = true;
  String? _error;
  String? _debugInfo;
  List<RsuRaceSummary> _races = const [];
  String? _selectedRaceId;
  int _timeout = 20;

  bool get _debugEnabled {
    final fromQuery = Uri.base.queryParameters['debug'] == '1';
    if (fromQuery) return true;

    final frag = Uri.base.fragment;
    final qIndex = frag.indexOf('?');
    if (qIndex == -1) return false;
    final fragQuery = frag.substring(qIndex + 1);
    return Uri.splitQueryString(fragQuery)['debug'] == '1';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final appState = context.read<RsuAppState>();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await appState.prepareForApiCall();

      final token = appState.accessToken;
      final range = appState.dateRange;

      if (token == null || range == null) throw Exception('Not authenticated');

      final timerKey = appState.timerApiKey;
      final timerSecret = appState.timerApiSecret;

      final timerKeyOk = (timerKey ?? '').trim().isNotEmpty;
      final timerSecretOk = (timerSecret ?? '').trim().isNotEmpty;

      debugPrint('RacePicker: list races using creds: timerKey=$timerKeyOk timerSecret=$timerSecretOk');

      // Important: if Timer credentials are missing, the upstream `/rest/races` call will return the public
      // catalog, which makes it look like we have access to “all races”. That’s misleading in the Timer
      // workflow, where the creds should naturally restrict what you can access.
      if (!timerKeyOk || !timerSecretOk) {
        throw Exception(
          'Timer API credentials are missing on this device.\n\n'
          'Expected: rsu_api_key (query param) + X-RSU-API-SECRET (header).\n'
          'Fix: open Global Settings and set them, or ensure they exist in Firestore so this device can hydrate them after login.',
        );
      }

      final api = RsuApi();
      final result = await api.listRacesWithResultsWithDebug(
        accessToken: token,
        range: range,
        timerApiKey: timerKey,
        timerApiSecret: timerSecret,
        onlyPartnerRaces: false,
        onlyRacesWithResults: true,
      );
      if (!mounted) return;

      final timerKeySet = (appState.timerApiKey ?? '').trim().isNotEmpty;
      final timerSecretSet = (appState.timerApiSecret ?? '').trim().isNotEmpty;

      setState(() {
        _races = result.races;
        _selectedRaceId = appState.raceId ?? (result.races.isNotEmpty ? result.races.first.raceId : null);
        _timeout = appState.timeoutSeconds;
        _debugInfo = [
          result.debug.toMultilineString(),
          '',
          '--- credential presence (local) ---',
          'firebaseSignedIn: ${FirebaseAuth.instance.currentUser != null}',
          'timerApiKey: ${timerKeySet ? 'set' : 'missing'}',
          'timerApiSecret: ${timerSecretSet ? 'set' : 'missing'}',
        ].join('\n');
        _error = result.races.isNotEmpty ? null : 'No races were parsed.';
      });
    } catch (e) {
      debugPrint('Load races failed: $e');
      setState(() {
        _error = '$e';
        _debugInfo ??= 'Load threw before debug data could be captured.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _maybePromptForLogoutCode(BuildContext context, {required RsuAppState appState}) async {
    if ((appState.logoutCode ?? '').trim().isNotEmpty) return true;

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final codeController = TextEditingController();

    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        builder: (context) {
          var reveal = false;
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final code = codeController.text.trim();
              final canSave = code.isNotEmpty;

              return SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Set a logout code?', style: textTheme.titleLarge, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text('Optional. If set, you must enter it to log out on this device.', style: textTheme.bodyMedium, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          TextField(
                            controller: codeController,
                            keyboardType: TextInputType.visiblePassword,
                            obscureText: !reveal,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Logout code',
                              hintText: 'Enter a code',
                              suffixIcon: IconButton(
                                tooltip: reveal ? 'Hide code' : 'Show code',
                                onPressed: () => setSheetState(() => reveal = !reveal),
                                icon: Icon(reveal ? Icons.visibility_off : Icons.visibility, color: cs.primary),
                              ),
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: canSave ? () => context.pop(true) : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.actionOrange,
                              foregroundColor: AppColors.onActionOrange,
                              minimumSize: const Size.fromHeight(54),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              splashFactory: NoSplash.splashFactory,
                            ),
                            icon: const Icon(Icons.lock, color: AppColors.onActionOrange),
                            label: const Text('Save code & continue', style: TextStyle(color: AppColors.onActionOrange)),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () => context.pop(false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              splashFactory: NoSplash.splashFactory,
                            ),
                            child: Text('Skip for now', style: TextStyle(color: cs.primary)),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => context.pop(null),
                            style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory),
                            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (result == null) return false;
      if (result == true) await appState.setLogoutCode(codeController.text.trim());
      return true;
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _continue() async {
    final raceId = _selectedRaceId;
    if (raceId == null || raceId.isEmpty) return;
    final appState = context.read<RsuAppState>();

    final ok = await _maybePromptForLogoutCode(context, appState: appState);
    if (!ok) return;

    await appState.setRaceId(raceId);
    await appState.setTimeoutSeconds(_timeout);
    if (!mounted) return;
    context.go('${AppRoutes.search}?raceId=$raceId');
  }

  InputDecoration _dropdownDecoration(BuildContext context, {required String label}) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.6), width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4), width: 2)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.primary, width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Event'),
        leading: IconButton(onPressed: () => context.go(AppRoutes.dates), icon: Icon(Icons.arrow_back, color: cs.primary)),
        actions: [
          IconButton(tooltip: 'Global settings', onPressed: () => context.push(AppRoutes.settingsGlobal), icon: Icon(Icons.manage_accounts_outlined, color: cs.primary)),
          IconButton(
            tooltip: 'Race settings',
            onPressed: _selectedRaceId == null ? null : () => context.push('${AppRoutes.settingsRace}?raceId=$_selectedRaceId'),
            icon: Icon(Icons.settings_outlined, color: _selectedRaceId == null ? cs.outline : cs.primary),
          ),
          const LogoutActionButton(),
        ],
      ),
      body: CenteredSurfacePanel(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Races', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: Icon(Icons.refresh, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              CopyableErrorPanel(message: _error!, title: 'Load races failed'),
              const SizedBox(height: 10),
            ],
            if (_debugEnabled || (_races.isEmpty && _debugInfo != null)) ...[
              CopyableErrorPanel(message: _debugInfo ?? 'No debug info yet (tap refresh).', title: _debugEnabled ? 'Debug (races list response)' : 'Diagnostics (why the list is empty)'),
              const SizedBox(height: 10),
            ],
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedRaceId,
              items: _races.map((r) => DropdownMenuItem(value: r.raceId, child: Text(r.name, overflow: TextOverflow.ellipsis))).toList(growable: false),
              decoration: _dropdownDecoration(context, label: 'Select an event'),
              onChanged: (v) => setState(() => _selectedRaceId = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _timeout,
              items: const [10, 15, 20, 25, 30, 45].map((s) => DropdownMenuItem(value: s, child: Text('$s seconds'))).toList(growable: false),
              decoration: _dropdownDecoration(context, label: 'Timeout'),
              onChanged: (v) => setState(() => _timeout = v ?? 20),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.actionOrange,
                foregroundColor: AppColors.onActionOrange,
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: (_selectedRaceId == null || _loading) ? null : _continue,
              icon: Icon(Icons.arrow_forward, color: AppColors.onActionOrange),
              label: Text('Select race', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.onActionOrange)),
            ),
            const SizedBox(height: 10),
            Text(
              'Tip: Settings are per-race (colors + sponsor logo).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
