import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/app_color_picker_sheet.dart';
import 'package:rsu_results/components/background_color_tile.dart';
import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/models.dart';

class RaceSettingsPage extends StatefulWidget {
  final String raceId;

  const RaceSettingsPage({super.key, required this.raceId});

  @override
  State<RaceSettingsPage> createState() => _RaceSettingsPageState();
}

class _RaceSettingsPageState extends State<RaceSettingsPage> {
  bool _loading = true;
  String? _error;

  RsuRaceThemeSettings? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await context.read<RsuAppState>().getRaceTheme(widget.raceId);
      setState(() => _settings = s);
    } catch (e) {
      debugPrint('Load settings failed: $e');
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final s = _settings;
    if (s == null) return;
    await context.read<RsuAppState>().setRaceTheme(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved'), behavior: SnackBarBehavior.floating));
  }

  Future<void> _pickSponsorLogo() async {
    final res = await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final mime = _guessMime(file.extension ?? '');
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';

    setState(() {
      _settings = (_settings ?? RsuRaceThemeSettings.defaultsForRace(widget.raceId)).copyWith(sponsorLogoDataUrl: dataUrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(onPressed: () => context.pop(), icon: Icon(Icons.arrow_back, color: cs.primary)),
        actions: [
          IconButton(
            tooltip: 'Global settings',
            onPressed: () => context.push(AppRoutes.settingsGlobal),
            icon: Icon(Icons.manage_accounts_outlined, color: cs.primary),
          ),
          const LogoutActionButton(),
        ],
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
                          Text('Race settings', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 10),
                          if (_error != null) ...[
                            CopyableErrorPanel(message: _error!, title: 'Load settings failed'),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 10),
                          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          BackgroundColorTile(
                            color: context.watch<RsuAppState>().pageBackgroundColor,
                            onTap: () async {
                              final app = context.read<RsuAppState>();
                              final picked = await AppColorPickerSheet.show(context, initialColor: app.pageBackgroundColor, title: 'Page background');
                              if (picked == null && app.pageBackgroundColor == null) return;
                              await app.setPageBackgroundColor(picked);
                            },
                          ),
                          const SizedBox(height: 18),
                          if (s != null) ...[
                            _ColorRow(
                              label: 'Results label color',
                              value: s.labelColorHex,
                              onChanged: (v) => setState(() => _settings = s.copyWith(labelColorHex: v)),
                            ),
                            _ColorRow(
                              label: 'Results data color',
                              value: s.dataColorHex,
                              onChanged: (v) => setState(() => _settings = s.copyWith(dataColorHex: v)),
                            ),
                            _ColorRow(
                              label: 'Participant name color',
                              value: s.nameColorHex,
                              onChanged: (v) => setState(() => _settings = s.copyWith(nameColorHex: v)),
                            ),
                            _ColorRow(
                              label: 'Background color',
                              value: s.backgroundColorHex,
                              onChanged: (v) => setState(() => _settings = s.copyWith(backgroundColorHex: v)),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _pickSponsorLogo,
                              icon: Icon(Icons.image_outlined, color: cs.primary),
                              label: Text('Upload sponsor logo', style: TextStyle(color: cs.primary)),
                            ),
                            const SizedBox(height: 10),
                            if (s.sponsorLogoDataUrl.isNotEmpty) ...[
                              const Text('Current sponsor logo:'),
                              const SizedBox(height: 8),
                              _SponsorLogoThumb(dataUrl: s.sponsorLogoDataUrl),
                              const SizedBox(height: 10),
                            ],
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _save,
                              icon: Icon(Icons.save_outlined, color: cs.onPrimary),
                              label: Text('Save', style: TextStyle(color: cs.onPrimary)),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _guessMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }
}

class _ColorRow extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _ColorRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              final initial = _colorFromHex(value) ?? cs.primary;
              final picked = await AppColorPickerSheet.show(context, initialColor: initial, title: label);
              if (picked == null) return;
              onChanged(_toHex(picked));
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 32,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: _colorFromHex(value) ?? cs.primary, border: Border.all(color: cs.outline.withValues(alpha: 0.25))),
            ),
          ),
        ],
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

  static String _toHex(Color c) {
    final v = c.value & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }
}


class _SponsorLogoThumb extends StatelessWidget {
  final String dataUrl;

  const _SponsorLogoThumb({required this.dataUrl});

  @override
  Widget build(BuildContext context) {
    try {
      final idx = dataUrl.indexOf(',');
      final b64 = idx < 0 ? '' : dataUrl.substring(idx + 1);
      final bytes = base64Decode(b64);
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(bytes, height: 70, fit: BoxFit.contain));
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
