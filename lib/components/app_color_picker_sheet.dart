import 'package:flutter/material.dart';

class AppColorPickerSheet extends StatefulWidget {
  final Color? initialColor;
  final String title;
  final bool allowAlpha;

  const AppColorPickerSheet({super.key, required this.initialColor, this.title = 'Pick a color', this.allowAlpha = false});

  static Future<Color?> show(BuildContext context, {required Color? initialColor, String title = 'Pick a color', bool allowAlpha = false}) {
    return showModalBottomSheet<Color?>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AppColorPickerSheet(initialColor: initialColor, title: title, allowAlpha: allowAlpha),
    );
  }

  @override
  State<AppColorPickerSheet> createState() => _AppColorPickerSheetState();
}

class _AppColorPickerSheetState extends State<AppColorPickerSheet> {
  static const _swatches = <Color>[
    Color(0xFFF7F9FA),
    Color(0xFFFBFCFD),
    Color(0xFFFFFFFF),
    Color(0xFFF1F5F9),
    Color(0xFFEFF6FF),
    Color(0xFFF5F3FF),
    Color(0xFFFFF7ED),
    Color(0xFFFFF1F2),
    Color(0xFF0B1220),
    Color(0xFF111827),
    Color(0xFF1A1C1E),
    Color(0xFF0F172A),
  ];

  late Color? _selected;
  final _hexCtrl = TextEditingController();
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
    _hexCtrl.text = _selected == null ? '' : _toHex(_selected!, allowAlpha: widget.allowAlpha);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final preview = _selected;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _ColorPreviewRow(color: preview, onClear: () => setState(() {
                _selected = null;
                _hexCtrl.text = '';
                _hexError = null;
              })),
              const SizedBox(height: 16),
              Text('Sliders', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _RgbSliders(
                allowAlpha: widget.allowAlpha,
                color: _selected ?? widget.initialColor ?? Theme.of(context).colorScheme.primary,
                onChanged: (c) => setState(() {
                  _selected = c;
                  _hexCtrl.text = _toHex(c, allowAlpha: widget.allowAlpha);
                  _hexError = null;
                }),
              ),
              const SizedBox(height: 18),
              Text('Swatches', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in _swatches)
                    _SwatchDot(
                      color: c,
                      selected: _selected?.toARGB32() == c.toARGB32(),
                      onTap: () => setState(() {
                        _selected = c;
                        _hexCtrl.text = _toHex(c, allowAlpha: widget.allowAlpha);
                        _hexError = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text('Hex', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              TextField(
                controller: _hexCtrl,
                decoration: InputDecoration(
                  prefixText: '#',
                  labelText: widget.allowAlpha ? 'AARRGGBB or RRGGBB' : 'RRGGBB',
                  errorText: _hexError,
                ),
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) => _applyHex(v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(widget.initialColor),
                      child: Text('Cancel', style: TextStyle(color: cs.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: Text('Apply', style: TextStyle(color: cs.onPrimary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyHex(String raw) {
    final cleaned = raw.replaceAll('#', '').trim();
    if (cleaned.isEmpty) {
      setState(() {
        _hexError = null;
        _selected = null;
      });
      return;
    }

    final parsed = _tryParseHex(cleaned, allowAlpha: widget.allowAlpha);
    setState(() {
      if (parsed == null) {
        _hexError = widget.allowAlpha ? 'Enter AARRGGBB or RRGGBB' : 'Enter RRGGBB';
      } else {
        _hexError = null;
        _selected = parsed;
      }
    });
  }

  static String _toHex(Color c, {required bool allowAlpha}) {
    final v = c.toARGB32();
    final a = (v >> 24) & 0xFF;
    final r = (v >> 16) & 0xFF;
    final g = (v >> 8) & 0xFF;
    final b = v & 0xFF;
    if (allowAlpha) {
      return '${a.toRadixString(16).padLeft(2, '0')}${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
    }
    return '${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  static Color? _tryParseHex(String hex, {required bool allowAlpha}) {
    final h = hex.toUpperCase();
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(h)) return null;

    if (allowAlpha) {
      if (h.length == 8) {
        final v = int.tryParse(h, radix: 16);
        if (v == null) return null;
        return Color(v);
      }
      if (h.length == 6) {
        final v = int.tryParse(h, radix: 16);
        if (v == null) return null;
        return Color(0xFF000000 | v);
      }
      return null;
    }

    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}

class _ColorPreviewRow extends StatelessWidget {
  final Color? color;
  final VoidCallback onClear;

  const _ColorPreviewRow({required this.color, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? Theme.of(context).scaffoldBackgroundColor;
    final isDefault = color == null;

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.35)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isDefault ? 'Default' : 'Custom', style: Theme.of(context).textTheme.titleMedium),
              Text(
                isDefault ? 'Uses the app theme background.' : 'Applies app-wide page background.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onClear,
          child: Text('Reset', style: TextStyle(color: cs.primary)),
        ),
      ],
    );
  }
}

class _RgbSliders extends StatefulWidget {
  final Color color;
  final bool allowAlpha;
  final ValueChanged<Color> onChanged;

  const _RgbSliders({required this.color, required this.allowAlpha, required this.onChanged});

  @override
  State<_RgbSliders> createState() => _RgbSlidersState();
}

class _RgbSlidersState extends State<_RgbSliders> {
  late double _r;
  late double _g;
  late double _b;
  late double _a;

  @override
  void initState() {
    super.initState();
    _syncFromColor(widget.color);
  }

  @override
  void didUpdateWidget(covariant _RgbSliders oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color.toARGB32() != widget.color.toARGB32()) _syncFromColor(widget.color);
  }

  void _syncFromColor(Color c) {
    _r = (c.r * 255.0).roundToDouble().clamp(0, 255);
    _g = (c.g * 255.0).roundToDouble().clamp(0, 255);
    _b = (c.b * 255.0).roundToDouble().clamp(0, 255);
    _a = (c.a * 255.0).roundToDouble().clamp(0, 255);
  }

  Color _build() => Color.fromARGB(_a.round(), _r.round(), _g.round(), _b.round());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = _build();

    return Column(
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: current,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
          ),
        ),
        const SizedBox(height: 12),
        _ChannelSlider(label: 'R', value: _r, max: 255, activeColor: Colors.red, onChanged: (v) => setState(() {
          _r = v;
          widget.onChanged(_build());
        })),
        _ChannelSlider(label: 'G', value: _g, max: 255, activeColor: Colors.green, onChanged: (v) => setState(() {
          _g = v;
          widget.onChanged(_build());
        })),
        _ChannelSlider(label: 'B', value: _b, max: 255, activeColor: Colors.blue, onChanged: (v) => setState(() {
          _b = v;
          widget.onChanged(_build());
        })),
        if (widget.allowAlpha)
          _ChannelSlider(label: 'A', value: _a, max: 255, activeColor: cs.primary, onChanged: (v) => setState(() {
            _a = v;
            widget.onChanged(_build());
          })),
      ],
    );
  }
}

class _ChannelSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  const _ChannelSlider({required this.label, required this.value, required this.max, required this.activeColor, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 22, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: activeColor, thumbColor: activeColor, inactiveTrackColor: cs.outline.withValues(alpha: 0.20)),
            child: Slider(value: value.clamp(0, max), max: max, divisions: max.round(), label: value.round().toString(), onChanged: onChanged),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 38, child: Text(value.round().toString(), textAlign: TextAlign.right, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

class _SwatchDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchDot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? cs.primary : cs.outline.withValues(alpha: 0.35), width: selected ? 2 : 1),
        ),
        child: selected ? Icon(Icons.check_rounded, color: cs.primary) : null,
      ),
    );
  }
}
