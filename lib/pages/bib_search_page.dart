import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/components/remote_logo_image.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/models.dart';
import 'package:rsu_results/rsu/rsu_api.dart';
import 'package:rsu_results/theme.dart';

class BibSearchPage extends StatefulWidget {
  final String raceId;

  const BibSearchPage({super.key, required this.raceId});

  @override
  State<BibSearchPage> createState() => _BibSearchPageState();
}

class _BibSearchPageState extends State<BibSearchPage> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _queryFocus = FocusNode();

  bool _loadingRace = true;
  String? _error;
  RsuRaceDetails? _race;
  RsuRaceThemeSettings? _theme;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRace());
    _query.addListener(() {
      if (!mounted) return;
      // Update keypad visibility + hint text reactively.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  Future<void> _loadRace() async {
    setState(() {
      _loadingRace = true;
      _error = null;
    });

    try {
      final appState = context.read<RsuAppState>();
      await appState.prepareForApiCall();
      final token = appState.accessToken;
      final theme = await appState.getRaceTheme(widget.raceId);

      if (token == null) throw Exception('Not authenticated');
      final api = RsuApi();
      final race = await api.getRace(accessToken: token, raceId: widget.raceId, timerApiKey: appState.timerApiKey, timerApiSecret: appState.timerApiSecret);
      debugPrint('Loaded race ${race.raceId} "${race.name}" logoUrl="${race.logoUrl}"');
      if (!mounted) return;
      setState(() {
        _race = race;
        _theme = theme;
      });
    } catch (e) {
      debugPrint('Load race failed: $e');
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingRace = false);
    }
  }

  bool get _showNumericKeypad {
    // If they haven’t typed anything, assume they’re likely doing bib entry.
    final v = _query.text.trim();
    if (v.isEmpty) return true;
    return RegExp(r'^\d+$').hasMatch(v);
  }

  void _appendDigit(String d) {
    if (!_showNumericKeypad) return;
    final next = (_query.text + d).replaceAll(RegExp(r'\D+'), '');
    _query.text = next;
    _query.selection = TextSelection.collapsed(offset: _query.text.length);
  }

  void _deleteChar() {
    if (_query.text.isEmpty) return;
    _query.text = _query.text.substring(0, _query.text.length - 1);
    _query.selection = TextSelection.collapsed(offset: _query.text.length);
  }

  void _clear() {
    _query.clear();
  }

  Future<void> _search() async {
    final theme = _theme;
    if (theme == null) return;

    final raw = _query.text.trim();
    if (raw.isEmpty) {
      _toast('Please enter a bib number or runner last name');
      _queryFocus.requestFocus();
      return;
    }

    final isBib = RegExp(r'^\d+$').hasMatch(raw);
    if (isBib) {
      context.go('${AppRoutes.results}?raceId=${widget.raceId}&searchType=bib&bib=$raw');
    } else {
      context.go('${AppRoutes.results}?raceId=${widget.raceId}&searchType=name&name=${Uri.encodeComponent(raw)}');
    }
  }

  void _toast(String message) => CopyableSnackBar.show(context, message);

  @override
  Widget build(BuildContext context) {
    final race = _race;
    final theme = _theme;
    final appState = context.watch<RsuAppState>();
    final isKioskMode = appState.logoutCode != null && appState.logoutCode!.isNotEmpty;

    Color? background;
    if (theme != null) background = _colorFromHex(theme.backgroundColorHex);

    return PopScope(
      canPop: !isKioskMode,
      child: Scaffold(
      backgroundColor: background ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: null,
        automaticallyImplyLeading: false,
        actions: const [LogoutActionButton()],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: _LegacyBibSearchCard(
                loadingRace: _loadingRace,
                error: _error,
                race: race,
                theme: theme,
                queryController: _query,
                queryFocus: _queryFocus,
                showNumericKeypad: _showNumericKeypad,
                onDigit: _appendDigit,
                onClear: _clear,
                onDelete: _deleteChar,
                onSearch: _search,
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  static Color? _colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}

class _LegacyBibSearchCard extends StatelessWidget {
  final bool loadingRace;
  final String? error;
  final RsuRaceDetails? race;
  final RsuRaceThemeSettings? theme;
  final TextEditingController queryController;
  final FocusNode queryFocus;
  final bool showNumericKeypad;
  final ValueChanged<String> onDigit;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onSearch;

  const _LegacyBibSearchCard({
    required this.loadingRace,
    required this.error,
    required this.race,
    required this.theme,
    required this.queryController,
    required this.queryFocus,
    required this.showNumericKeypad,
    required this.onDigit,
    required this.onClear,
    required this.onDelete,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(color: cs.shadow.withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loadingRace) const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CircularProgressIndicator())),
            if (error != null) ...[
              const SizedBox(height: 10),
              CopyableErrorPanel(message: error!, title: 'Search failed'),
            ],
            if (!loadingRace && race != null) ...[
              _RaceLogos(logoUrl: race!.logoUrl, sponsorLogoDataUrl: theme?.sponsorLogoDataUrl ?? ''),
              const SizedBox(height: 12),
            ],
            _UnifiedSearchSection(
              controller: queryController,
              focusNode: queryFocus,
              showNumericKeypad: showNumericKeypad,
              onDigit: onDigit,
              onClear: onClear,
              onDelete: onDelete,
              onSubmitted: onSearch,
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: enter bib digits to search by bib, or type a name to search by last name.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedSearchSection extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showNumericKeypad;
  final ValueChanged<String> onDigit;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback onSubmitted;

  const _UnifiedSearchSection({
    required this.controller,
    required this.focusNode,
    required this.showNumericKeypad,
    required this.onDigit,
    required this.onClear,
    required this.onDelete,
    required this.onSubmitted,
  });

  bool _isDigitsOnly(String v) => v.trim().isNotEmpty && RegExp(r'^\d+$').hasMatch(v.trim());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trimmed = controller.text.trim();
    final digitsOnly = _isDigitsOnly(trimmed);

    final hint = digitsOnly || trimmed.isEmpty ? 'Type bib number (digits only) or name' : 'Type name (last name works best)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _LegacyTextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.search,
                hintText: hint,
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.actionOrange,
                  foregroundColor: AppColors.onActionOrange,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onSubmitted,
                icon: const Icon(Icons.search, size: 22),
                label: const Text('Find', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: showNumericKeypad
              ? Column(
                  key: const ValueKey('keypad'),
                  children: [
                    _LegacyNumericKeypad(onDigit: onDigit, onClear: onClear, onDelete: onDelete),
                    const SizedBox(height: 6),
                    Text('CLR clears • DEL deletes', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.85))),
                  ],
                )
              : Row(
                  key: const ValueKey('textActions'),
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHighest,
                          foregroundColor: cs.onSurface,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onClear,
                        child: Text('Clear', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiaryContainer,
                          foregroundColor: cs.onTertiaryContainer,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: onDelete,
                        child: Text('Delete', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LegacyTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  const _LegacyTextField({
    required this.controller,
    required this.focusNode,
    required this.keyboardType,
    required this.hintText,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.6), width: 2)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4), width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.primary, width: 2)),
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _RaceLogos extends StatelessWidget {
  final String logoUrl;
  final String sponsorLogoDataUrl;

  const _RaceLogos({required this.logoUrl, required this.sponsorLogoDataUrl});

  static String _normalizeRemoteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('http://')) return 'https://${u.substring('http://'.length)}';
    if (u.startsWith('/')) return 'https://runsignup.com$u';
    if (!u.startsWith('http://') && !u.startsWith('https://')) return 'https://runsignup.com/$u';
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    final normalizedLogo = _normalizeRemoteUrl(logoUrl);
    if (normalizedLogo.isNotEmpty) {
      widgets.add(RemoteLogoImage(url: normalizedLogo, height: 72));
    }
    if (sponsorLogoDataUrl.isNotEmpty) {
      final bytes = _tryDecodeDataUrl(sponsorLogoDataUrl);
      if (bytes != null) widgets.add(Image.memory(bytes, height: 72, fit: BoxFit.contain));
    }
    if (widgets.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: widgets,
            ),
          ),
        ],
      ),
    );
  }

  static Uint8List? _tryDecodeDataUrl(String dataUrl) {
    try {
      final idx = dataUrl.indexOf(',');
      if (idx < 0) return null;
      final b64 = dataUrl.substring(idx + 1);
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }
}

class _LegacyNumericKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const _LegacyNumericKeypad({required this.onDigit, required this.onClear, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: [
        for (final d in digits) _LegacyKeyButton(label: d, onPressed: () => onDigit(d)),
        _LegacyKeyButton(label: 'CLR', onPressed: onClear, background: cs.error, foreground: cs.onError),
        _LegacyKeyButton(label: '0', onPressed: () => onDigit('0')),
        _LegacyKeyButton(label: 'DEL', onPressed: onDelete, background: cs.secondary, foreground: cs.onSecondary),
      ],
    );
  }
}

class _LegacyKeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? background;
  final Color? foreground;

  const _LegacyKeyButton({required this.label, required this.onPressed, this.background, this.foreground});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.surfaceContainerHighest;
    final fg = foreground ?? cs.onSurface;

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        splashFactory: NoSplash.splashFactory,
      ),
      onPressed: onPressed,
      child: Text(label, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
    );
  }
}
