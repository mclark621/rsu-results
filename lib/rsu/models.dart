import 'package:rsu_results/rsu/race_text_style_config.dart';

class RsuRaceSummary {
  final String raceId;
  final String name;

  const RsuRaceSummary({required this.raceId, required this.name});

  /// RunSignup responses are not fully consistent across endpoints/params.
  /// We may receive either:
  ///  - { "race": { "race_id": ..., "name": ... } }
  ///  - { "race_id": ..., "name": ... }
  factory RsuRaceSummary.fromJson(Map<String, dynamic> json) {
    final dynamic raceNode = json['race'];
    final Map<String, dynamic> race = (raceNode is Map ? raceNode.cast<String, dynamic>() : null) ?? json;
    return RsuRaceSummary(raceId: '${race['race_id'] ?? ''}', name: '${race['name'] ?? ''}');
  }
}

class RsuRaceDetails {
  final String raceId;
  final String name;
  final String logoUrl;
  final List<RsuRaceEvent> events;

  const RsuRaceDetails({required this.raceId, required this.name, required this.logoUrl, required this.events});

  /// RunSignup response shapes vary by endpoint/params. Common variants include:
  /// - { "race": { ... } }
  /// - { "race": [ { ... } ] }
  /// - { "race_id": ..., "name": ... } (race object at the top level)
  factory RsuRaceDetails.fromJson(Map<String, dynamic> json) {
    final dynamic raceNode = json['race'];

    Map<String, dynamic> race;
    if (raceNode is Map) {
      race = raceNode.cast<String, dynamic>();
    } else if (raceNode is List && raceNode.isNotEmpty && raceNode.first is Map) {
      race = (raceNode.first as Map).cast<String, dynamic>();
    } else if (json.containsKey('race_id') || json.containsKey('logo_url') || json.containsKey('name')) {
      race = json;
    } else {
      race = const <String, dynamic>{};
    }

    // Some RSU responses wrap the race payload multiple times (e.g. {race: {race: {...}}}).
    while (race.length == 1 && race['race'] != null) {
      final nested = race['race'];
      if (nested is Map) {
        race = nested.cast<String, dynamic>();
        continue;
      }
      if (nested is List && nested.isNotEmpty && nested.first is Map) {
        race = (nested.first as Map).cast<String, dynamic>();
        continue;
      }
      break;
    }

    final eventsRaw = (race['events'] as List?) ?? const [];

    // Per the official Get Race spec, race.logo_url is the race logo URL.
    // Some older payloads may use "logo" instead.
    final rawLogo = '${race['logo_url'] ?? race['logo'] ?? json['logo_url'] ?? ''}'.trim();
    final logoUrl = _normalizeRemoteUrl(rawLogo);

    return RsuRaceDetails(
      raceId: '${race['race_id'] ?? json['race_id'] ?? ''}',
      name: '${race['name'] ?? json['name'] ?? ''}',
      logoUrl: logoUrl,
      events: eventsRaw.whereType<Map>().map((e) => RsuRaceEvent.fromJson(e.cast<String, dynamic>())).toList(growable: false),
    );
  }

  static String _normalizeRemoteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';

    // Common cases returned by RunSignup.
    if (u.startsWith('//')) return 'https:$u';

    // Prevent mixed-content blocking on web when app is served over https.
    if (u.startsWith('http://')) return 'https://${u.substring('http://'.length)}';

    // Sometimes an endpoint returns a root-relative path.
    if (u.startsWith('/')) return 'https://runsignup.com$u';

    // Occasionally we see a path-like value without a scheme/host.
    if (!u.startsWith('http://') && !u.startsWith('https://')) return 'https://runsignup.com/$u';

    return u;
  }
}

class RsuRaceEvent {
  final String eventId;
  final String name;
  final DateTime? startTime;
  final String raceEventDaysId;

  const RsuRaceEvent({required this.eventId, required this.name, required this.startTime, required this.raceEventDaysId});

  factory RsuRaceEvent.fromJson(Map<String, dynamic> json) {
    final start = json['start_time'];
    DateTime? startTime;
    if (start is String && start.isNotEmpty) {
      startTime = DateTime.tryParse(start);
    }
    return RsuRaceEvent(
      eventId: '${json['event_id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      startTime: startTime,
      raceEventDaysId: '${json['race_event_days_id'] ?? ''}',
    );
  }
}

class RsuCandidate {
  final String bib;
  final String firstName;
  final String lastName;
  final String gender;
  final String age;
  final String city;
  final String state;
  final String event;

  const RsuCandidate({
    required this.bib,
    required this.firstName,
    required this.lastName,
    required this.gender,
    required this.age,
    required this.city,
    required this.state,
    required this.event,
  });

  String get displayName {
    final name = '${firstName.trim()} ${lastName.trim()}'.trim();
    return name.isEmpty ? '-' : name;
  }
}

class RsuEventResult {
  final String eventName;
  final String bib;
  final String firstName;
  final String lastName;
  final String chipTime;
  final String pace;
  final String place;

  /// RunSignup division header/code for placement (e.g. `M3034`). Map for display labels: `rsuAgeGroupDisplayLabel()` in `age_group_display.dart`.
  final String divisionLabel;
  final String divisionPlace;
  final String genderPlace;
  final int finishers;
  final int genderFinishers;
  final int divisionFinishers;

  const RsuEventResult({
    required this.eventName,
    required this.bib,
    required this.firstName,
    required this.lastName,
    required this.chipTime,
    required this.pace,
    required this.place,
    required this.divisionLabel,
    required this.divisionPlace,
    required this.genderPlace,
    required this.finishers,
    required this.genderFinishers,
    required this.divisionFinishers,
  });
}

class RsuRaceThemeSettings {
  final String raceId;
  final String labelColorHex;
  final String dataColorHex;
  final String nameColorHex;
  final String backgroundColorHex;
  final String sponsorLogoDataUrl;
  final RsuRaceTextStyleConfig participantNameStyle;
  final RsuRaceTextStyleConfig chipTimeStyle;
  final RsuRaceTextStyleConfig finisherLineStyle;
  final RsuRaceTextStyleConfig metricLabelStyle;
  final RsuRaceTextStyleConfig metricValueStyle;
  final RsuRaceTextStyleConfig emptyStateTitleStyle;

  const RsuRaceThemeSettings({
    required this.raceId,
    required this.labelColorHex,
    required this.dataColorHex,
    required this.nameColorHex,
    required this.backgroundColorHex,
    required this.sponsorLogoDataUrl,
    required this.participantNameStyle,
    required this.chipTimeStyle,
    required this.finisherLineStyle,
    required this.metricLabelStyle,
    required this.metricValueStyle,
    required this.emptyStateTitleStyle,
  });

  RsuRaceThemeSettings copyWith({
    String? labelColorHex,
    String? dataColorHex,
    String? nameColorHex,
    String? backgroundColorHex,
    String? sponsorLogoDataUrl,
    RsuRaceTextStyleConfig? participantNameStyle,
    RsuRaceTextStyleConfig? chipTimeStyle,
    RsuRaceTextStyleConfig? finisherLineStyle,
    RsuRaceTextStyleConfig? metricLabelStyle,
    RsuRaceTextStyleConfig? metricValueStyle,
    RsuRaceTextStyleConfig? emptyStateTitleStyle,
  }) {
    return RsuRaceThemeSettings(
      raceId: raceId,
      labelColorHex: labelColorHex ?? this.labelColorHex,
      dataColorHex: dataColorHex ?? this.dataColorHex,
      nameColorHex: nameColorHex ?? this.nameColorHex,
      backgroundColorHex: backgroundColorHex ?? this.backgroundColorHex,
      sponsorLogoDataUrl: sponsorLogoDataUrl ?? this.sponsorLogoDataUrl,
      participantNameStyle: participantNameStyle ?? this.participantNameStyle,
      chipTimeStyle: chipTimeStyle ?? this.chipTimeStyle,
      finisherLineStyle: finisherLineStyle ?? this.finisherLineStyle,
      metricLabelStyle: metricLabelStyle ?? this.metricLabelStyle,
      metricValueStyle: metricValueStyle ?? this.metricValueStyle,
      emptyStateTitleStyle: emptyStateTitleStyle ?? this.emptyStateTitleStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'raceId': raceId,
    'labelColorHex': labelColorHex,
    'dataColorHex': dataColorHex,
    'nameColorHex': nameColorHex,
    'backgroundColorHex': backgroundColorHex,
    'sponsorLogoDataUrl': sponsorLogoDataUrl,
    'typography': {
      'participantName': participantNameStyle.toJson(),
      'chipTime': chipTimeStyle.toJson(),
      'finisherLine': finisherLineStyle.toJson(),
      'metricLabel': metricLabelStyle.toJson(),
      'metricValue': metricValueStyle.toJson(),
      'emptyStateTitle': emptyStateTitleStyle.toJson(),
    },
  };

  factory RsuRaceThemeSettings.fromJson(Map<String, dynamic> json) {
    final typo = json['typography'];
    final typoMap = typo is Map ? typo.cast<String, dynamic>() : const <String, dynamic>{};

    Map<String, dynamic>? typoRole(String k) {
      final v = typoMap[k];
      return v is Map ? v.cast<String, dynamic>() : null;
    }

    return RsuRaceThemeSettings(
      raceId: '${json['raceId'] ?? ''}',
      labelColorHex: '${json['labelColorHex'] ?? '#90D5FF'}',
      dataColorHex: '${json['dataColorHex'] ?? '#d1842a'}',
      nameColorHex: '${json['nameColorHex'] ?? '#000000'}',
      backgroundColorHex: '${json['backgroundColorHex'] ?? '#f4f7f6'}',
      sponsorLogoDataUrl: '${json['sponsorLogoDataUrl'] ?? ''}',
      participantNameStyle: RsuRaceTextStyleConfig.fromJson(typoRole('participantName'), RsuRaceTypographyDefaults.participantName),
      chipTimeStyle: RsuRaceTextStyleConfig.fromJson(typoRole('chipTime'), RsuRaceTypographyDefaults.chipTime),
      finisherLineStyle: RsuRaceTextStyleConfig.fromJson(typoRole('finisherLine'), RsuRaceTypographyDefaults.finisherLine),
      metricLabelStyle: RsuRaceTextStyleConfig.fromJson(typoRole('metricLabel'), RsuRaceTypographyDefaults.metricLabel),
      metricValueStyle: RsuRaceTextStyleConfig.fromJson(typoRole('metricValue'), RsuRaceTypographyDefaults.metricValue),
      emptyStateTitleStyle: RsuRaceTextStyleConfig.fromJson(typoRole('emptyStateTitle'), RsuRaceTypographyDefaults.emptyStateTitle),
    );
  }

  static RsuRaceThemeSettings defaultsForRace(String raceId) => RsuRaceThemeSettings(
    raceId: raceId,
    labelColorHex: '#90D5FF',
    dataColorHex: '#d1842a',
    nameColorHex: '#000000',
    backgroundColorHex: '#f4f7f6',
    sponsorLogoDataUrl: '',
    participantNameStyle: RsuRaceTypographyDefaults.participantName,
    chipTimeStyle: RsuRaceTypographyDefaults.chipTime,
    finisherLineStyle: RsuRaceTypographyDefaults.finisherLine,
    metricLabelStyle: RsuRaceTypographyDefaults.metricLabel,
    metricValueStyle: RsuRaceTypographyDefaults.metricValue,
    emptyStateTitleStyle: RsuRaceTypographyDefaults.emptyStateTitle,
  );
}
