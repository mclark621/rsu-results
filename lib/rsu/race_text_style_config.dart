import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Serializable typography for one results-screen text role.
class RsuRaceTextStyleConfig {
  final String fontKey;
  final double fontSize;
  final int fontWeight;
  final bool italic;
  final double letterSpacing;
  final double height;

  const RsuRaceTextStyleConfig({
    required this.fontKey,
    required this.fontSize,
    required this.fontWeight,
    required this.italic,
    required this.letterSpacing,
    required this.height,
  });

  RsuRaceTextStyleConfig copyWith({
    String? fontKey,
    double? fontSize,
    int? fontWeight,
    bool? italic,
    double? letterSpacing,
    double? height,
  }) {
    return RsuRaceTextStyleConfig(
      fontKey: fontKey ?? this.fontKey,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      italic: italic ?? this.italic,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontKey': fontKey,
    'fontSize': fontSize,
    'fontWeight': fontWeight,
    'italic': italic,
    'letterSpacing': letterSpacing,
    'height': height,
  };

  factory RsuRaceTextStyleConfig.fromJson(Map<String, dynamic>? json, RsuRaceTextStyleConfig fallback) {
    if (json == null) return fallback;
    return RsuRaceTextStyleConfig(
      fontKey: '${json['fontKey'] ?? fallback.fontKey}',
      fontSize: _readDouble(json['fontSize'], fallback.fontSize),
      fontWeight: _readInt(json['fontWeight'], fallback.fontWeight),
      italic: json['italic'] == true,
      letterSpacing: _readDouble(json['letterSpacing'], fallback.letterSpacing),
      height: _readDouble(json['height'], fallback.height),
    );
  }

  static double _readDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static int _readInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}

/// Curated Google Font keys we support in settings (must match [_googleFont]).
class RaceFontOption {
  final String key;
  final String label;

  const RaceFontOption({required this.key, required this.label});
}

const List<RaceFontOption> kRaceFontOptions = [
  RaceFontOption(key: 'alfaSlabOne', label: 'Alfa Slab One'),
  RaceFontOption(key: 'rubikDistressed', label: 'Rubik Distressed'),
  RaceFontOption(key: 'inter', label: 'Inter'),
  RaceFontOption(key: 'roboto', label: 'Roboto'),
  RaceFontOption(key: 'oswald', label: 'Oswald'),
  RaceFontOption(key: 'lato', label: 'Lato'),
  RaceFontOption(key: 'montserrat', label: 'Montserrat'),
  RaceFontOption(key: 'poppins', label: 'Poppins'),
  RaceFontOption(key: 'bebasNeue', label: 'Bebas Neue'),
  RaceFontOption(key: 'merriweather', label: 'Merriweather'),
];

/// Default typography matching the original hard-coded results screen.
class RsuRaceTypographyDefaults {
  RsuRaceTypographyDefaults._();

  static const RsuRaceTextStyleConfig participantName = RsuRaceTextStyleConfig(
    fontKey: 'alfaSlabOne',
    fontSize: 46,
    fontWeight: 400,
    italic: false,
    letterSpacing: 0.2,
    height: 1.0,
  );

  static const RsuRaceTextStyleConfig chipTime = RsuRaceTextStyleConfig(
    fontKey: 'rubikDistressed',
    fontSize: 86,
    fontWeight: 400,
    italic: false,
    letterSpacing: 0,
    height: 1.0,
  );

  static const RsuRaceTextStyleConfig finisherLine = RsuRaceTextStyleConfig(
    fontKey: 'rubikDistressed',
    fontSize: 28,
    fontWeight: 700,
    italic: false,
    letterSpacing: 0,
    height: 1.1,
  );

  static const RsuRaceTextStyleConfig metricLabel = RsuRaceTextStyleConfig(
    fontKey: 'alfaSlabOne',
    fontSize: 28,
    fontWeight: 700,
    italic: false,
    letterSpacing: 0,
    height: 1.1,
  );

  static const RsuRaceTextStyleConfig metricValue = RsuRaceTextStyleConfig(
    fontKey: 'rubikDistressed',
    fontSize: 22,
    fontWeight: 400,
    italic: false,
    letterSpacing: 0,
    height: 1.1,
  );

  static const RsuRaceTextStyleConfig emptyStateTitle = RsuRaceTextStyleConfig(
    fontKey: 'alfaSlabOne',
    fontSize: 28,
    fontWeight: 400,
    italic: false,
    letterSpacing: 0,
    height: 1.1,
  );
}

TextStyle _googleFont(
  String fontKey, {
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? height,
  Color? color,
}) {
  switch (fontKey) {
    case 'rubikDistressed':
      return GoogleFonts.rubikDistressed(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'inter':
      return GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'roboto':
      return GoogleFonts.roboto(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'oswald':
      return GoogleFonts.oswald(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'lato':
      return GoogleFonts.lato(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'montserrat':
      return GoogleFonts.montserrat(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'poppins':
      return GoogleFonts.poppins(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'bebasNeue':
      return GoogleFonts.bebasNeue(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'merriweather':
      return GoogleFonts.merriweather(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
    case 'alfaSlabOne':
    default:
      return GoogleFonts.alfaSlabOne(
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        color: color,
      );
  }
}

FontWeight _fontWeightFromInt(int v) {
  final clamped = v.clamp(100, 900);
  if (clamped >= 900) return FontWeight.w900;
  if (clamped >= 800) return FontWeight.w800;
  if (clamped >= 700) return FontWeight.w700;
  if (clamped >= 600) return FontWeight.w600;
  if (clamped >= 500) return FontWeight.w500;
  if (clamped >= 400) return FontWeight.w400;
  if (clamped >= 300) return FontWeight.w300;
  if (clamped >= 200) return FontWeight.w200;
  return FontWeight.w100;
}

/// Builds a [TextStyle] for results UI using race typography and layout [scale].
TextStyle buildRaceTextStyle(
  RsuRaceTextStyleConfig cfg, {
  required Color color,
  required double scale,
}) {
  final key = kRaceFontOptions.any((o) => o.key == cfg.fontKey) ? cfg.fontKey : 'alfaSlabOne';
  return _googleFont(
    key,
    fontSize: cfg.fontSize * scale,
    fontWeight: _fontWeightFromInt(cfg.fontWeight),
    fontStyle: cfg.italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: cfg.letterSpacing,
    height: cfg.height,
    color: color,
  );
}
