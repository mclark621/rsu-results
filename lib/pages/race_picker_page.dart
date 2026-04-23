import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web/web.dart' as web;

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

      final firebaseUser = FirebaseAuth.instance.currentUser;
      debugPrint('RacePicker: Firebase user = ${firebaseUser?.uid ?? "NULL"}');
      debugPrint('RacePicker: rsuUserId = ${appState.rsuUserId ?? "NULL"}');
      debugPrint('RacePicker: timerKey=${timerKeyOk ? "SET" : "MISSING"} timerSecret=${timerSecretOk ? "SET" : "MISSING"}');

      // Important: if Timer credentials are missing, the upstream `/rest/races` call will return the public
      // catalog, which makes it look like we have access to "all races". That's misleading in the Timer
      // workflow, where the creds should naturally restrict what you can access.
      if (!timerKeyOk || !timerSecretOk) {
        final firebaseSignedIn = firebaseUser != null;
        debugPrint('RacePicker: credentials missing. firebaseSignedIn=$firebaseSignedIn');
        setState(() {
          _error = [
            'Timer API credentials are missing on this device.',
            '',
            'Expected: rsu_api_key (query param) + X-RSU-API-SECRET (header).',
            'Fix: open Global Settings and set them, then Save (sync to server).',
            if (!firebaseSignedIn) ...[
              '',
              'Note: Firebase is not signed in right now, so this device cannot hydrate creds from Firestore. This usually resolves after signing in again.',
            ],
            '',
            'Debug info:',
            '  Firebase UID: ${firebaseUser?.uid ?? "null"}',
            '  RSU User ID: ${appState.rsuUserId ?? "null"}',
          ].join('\n');
        });
        return;
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

  Future<void> _continue() async {
    final raceId = _selectedRaceId;
    if (raceId == null || raceId.isEmpty) return;

    // Prompt for logout code before locking into kiosk mode
    final logoutCode = await _promptForLogoutCode();
    if (logoutCode == null) return; // User cancelled
    if (!mounted) return;

    final appState = context.read<RsuAppState>();
    await appState.setRaceId(raceId);
    await appState.setTimeoutSeconds(_timeout);
    await appState.setLogoutCode(logoutCode);
    if (!mounted) return;
    
    // Clear browser history on web to prevent back button from escaping kiosk mode
    if (kIsWeb) {
      try {
        final targetUrl = '#${AppRoutes.search}?raceId=$raceId';
        // Replace all history entries with the search page
        web.window.history.replaceState(null, '', targetUrl);
        debugPrint('KIOSK: Cleared browser history, replaced with $targetUrl');
      } catch (e) {
        debugPrint('KIOSK: Failed to clear browser history: $e');
      }
    }

    if (!mounted) return;
    context.go('${AppRoutes.search}?raceId=$raceId');
  }

  Future<String?> _promptForLogoutCode() async {
    final cs = Theme.of(context).colorScheme;
    final codeController = TextEditingController();
    String? errorText;
    bool obscureCode = true;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cs.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Set Logout Code', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'This code will be required to log out. Keep it safe — without it, you cannot exit kiosk mode.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                obscureText: obscureCode,
                decoration: InputDecoration(
                  labelText: 'Logout Code (4+ digits)',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  errorText: errorText,
                  suffixIcon: IconButton(
                    icon: Icon(obscureCode ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setSheetState(() => obscureCode = !obscureCode),
                  ),
                ),
                onChanged: (_) => setSheetState(() => errorText = null),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionOrange,
                  foregroundColor: AppColors.onActionOrange,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final code = codeController.text.trim();
                  if (code.length < 4) {
                    setSheetState(() => errorText = 'Code must be at least 4 characters');
                    return;
                  }
                  Navigator.of(ctx).pop(code);
                },
                child: const Text('Set Code & Continue', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
                ),
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
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
        title: null,
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
                Expanded(child: Text('Select Event', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: Icon(Icons.refresh, color: cs.primary)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the race you want to display results for.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45, color: cs.onSurfaceVariant.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              CopyableErrorPanel(message: _error!, title: 'Load races failed'),
              if ((_error ?? '').contains('Timer API credentials are missing')) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.actionOrange,
                          foregroundColor: AppColors.onActionOrange,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          splashFactory: NoSplash.splashFactory,
                        ),
                        onPressed: _loading ? null : () => context.push(AppRoutes.settingsGlobal),
                        icon: Icon(Icons.manage_accounts_outlined, color: AppColors.onActionOrange),
                        label: Text('Open Global Settings', style: TextStyle(color: AppColors.onActionOrange, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHighest,
                        foregroundColor: cs.onSurface,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        splashFactory: NoSplash.splashFactory,
                      ),
                      onPressed: _loading ? null : _load,
                      icon: Icon(Icons.refresh, color: cs.onSurface),
                      label: Text('Retry', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
            ],
            if (_debugEnabled || (_races.isEmpty && _debugInfo != null)) ...[
              CopyableErrorPanel(message: _debugInfo ?? 'No debug info yet (tap refresh).', title: _debugEnabled ? 'Debug (races list response)' : 'Diagnostics (why the list is empty)'),
              const SizedBox(height: 10),
            ],
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: _dropdownDecoration(context, label: 'Select an event'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedRaceId,
                  items: _races.map((r) => DropdownMenuItem(value: r.raceId, child: Text(r.name, overflow: TextOverflow.ellipsis))).toList(growable: false),
                  onChanged: (v) => setState(() => _selectedRaceId = v),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: _dropdownDecoration(context, label: 'Timeout'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _timeout,
                  items: const [10, 15, 20, 25, 30, 45].map((s) => DropdownMenuItem(value: s, child: Text('$s seconds'))).toList(growable: false),
                  onChanged: (v) => setState(() => _timeout = v ?? 20),
                ),
              ),
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
