import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:rsu_results/components/copyable_error_panel.dart';
import 'package:rsu_results/components/logout_action_button.dart';
import 'package:rsu_results/components/remote_logo_image.dart';
import 'package:rsu_results/nav.dart';
import 'package:rsu_results/rsu/age_group_display.dart';
import 'package:rsu_results/rsu/app_state.dart';
import 'package:rsu_results/rsu/models.dart';
import 'package:rsu_results/rsu/race_text_style_config.dart';
import 'package:rsu_results/rsu/rsu_api.dart';

class ResultsPage extends StatefulWidget {
  final String raceId;
  final String searchType;
  final String? bib;
  final String? name;

  const ResultsPage({super.key, required this.raceId, required this.searchType, this.bib, this.name});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  bool _loading = true;
  String? _error;

  Timer? _autoBackTimer;

  RsuRaceDetails? _race;
  RsuRaceThemeSettings? _theme;

  List<RsuCandidate> _candidates = const [];
  List<RsuEventResult> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _armAutoBackTimer();
      _load();
    });
  }

  @override
  void dispose() {
    _autoBackTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ResultsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _armAutoBackTimer();

    final changed = oldWidget.raceId != widget.raceId ||
        oldWidget.searchType != widget.searchType ||
        oldWidget.bib != widget.bib ||
        oldWidget.name != widget.name;

    // go_router will often reuse the same State object when navigating to the same
    // route with different query params (e.g. pick a bib from the candidate list).
    // In that case, initState won’t run again, so we must explicitly reload.
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }
  }

  void _armAutoBackTimer() {
    if (!mounted) return;
    final seconds = context.read<RsuAppState>().timeoutSeconds;
    if (seconds <= 0) {
      _autoBackTimer?.cancel();
      _autoBackTimer = null;
      return;
    }

    _autoBackTimer?.cancel();
    _autoBackTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      debugPrint('ResultsPage auto-timeout after ${seconds}s → back to search');
      context.go('${AppRoutes.search}?raceId=${widget.raceId}');
    });
  }

  Future<void> _load() async {
    _armAutoBackTimer();
    setState(() {
      _loading = true;
      _error = null;
      // Important: when switching from a name search (candidate list) to a bib search,
      // go_router often reuses the same State object. If we don't clear candidates here,
      // the UI will keep showing the picker even after bib results load.
      _candidates = const [];
      _results = const [];
    });

    try {
      final appState = context.read<RsuAppState>();
      await appState.prepareForApiCall();
      final token = appState.accessToken;
      final api = RsuApi();

      final theme = await appState.getRaceTheme(widget.raceId);
      _theme = theme;

      final bib = widget.searchType == 'bib' ? (widget.bib ?? '').trim() : '';
      final lastName = widget.searchType == 'name' ? (widget.name ?? '').trim() : '';

      if (token == null) throw Exception('Not authenticated');

      final race = await api.getRace(accessToken: token, raceId: widget.raceId, timerApiKey: appState.timerApiKey, timerApiSecret: appState.timerApiSecret, bibNum: bib.isEmpty ? null : bib, lastName: lastName.isEmpty ? null : lastName);
      debugPrint('Loaded race ${race.raceId} "${race.name}" logoUrl="${race.logoUrl}"');
      _race = race;

      final now = DateTime.now();
      String previousRaceEventDaysId = '';

      final baseParams = <String, String>{
        'most_recent_events_only': 'F',
        'include_division_finishers': 'T',
        'include_total_finishers': 'T',
      };
      if (lastName.isNotEmpty) {
        baseParams['last_name'] = lastName;
      } else {
        baseParams['bib_num'] = bib;
      }

      final candidates = <RsuCandidate>[];
      final results = <RsuEventResult>[];

      for (final ev in race.events) {
        final start = ev.startTime;
        if (start != null && start.isAfter(now)) continue;

        if (previousRaceEventDaysId.isNotEmpty && previousRaceEventDaysId != ev.raceEventDaysId && (start == null || start.isBefore(now))) break;
        previousRaceEventDaysId = ev.raceEventDaysId;

        final resultJson = await api.getEventResults(accessToken: token, raceId: widget.raceId, eventId: ev.eventId, baseParams: baseParams, timerApiKey: appState.timerApiKey, timerApiSecret: appState.timerApiSecret);
        final sets = (resultJson['individual_results_sets'] as List?) ?? const [];
        if (sets.isEmpty) continue;

        for (final set in sets.whereType<Map>()) {
          final setMap = set.cast<String, dynamic>();
          final eventName = '${setMap['event_name'] ?? ev.name}';
          final rows = (setMap['results'] as List?) ?? const [];
          if (rows.isEmpty) continue;

          if (lastName.isNotEmpty) {
            for (final row in rows.whereType<Map>()) {
              final r = row.cast<String, dynamic>();
              candidates.add(RsuCandidate(
                bib: '${r['bib'] ?? ''}',
                firstName: '${r['first_name'] ?? ''}',
                lastName: '${r['last_name'] ?? ''}',
                gender: '${r['gender'] ?? ''}',
                age: '${r['age'] ?? ''}',
                city: '${r['city'] ?? ''}',
                state: '${r['state'] ?? ''}',
                event: eventName,
              ));
            }
          }

          if (lastName.isEmpty) {
            final first = (rows.first as Map).cast<String, dynamic>();
            final bibValue = '${first['bib'] ?? ''}';
            final chip = '${first['chip_time'] ?? ''}';
            results.add(_parseEventResult(eventName: ev.name, row: first, setMap: setMap, chipTime: chip, bib: bibValue));
          }
        }
      }

      if (lastName.isNotEmpty) {
        final byBib = <String, RsuCandidate>{};
        for (final c in candidates) {
          if (c.bib.isEmpty) continue;
          byBib.putIfAbsent(c.bib, () => c);
        }
        final unique = byBib.values.toList(growable: false);
        if (unique.length == 1) {
          if (!mounted) return;
          context.go('${AppRoutes.results}?raceId=${widget.raceId}&searchType=bib&bib=${unique.first.bib}');
          return;
        }
        if (unique.length > 1) {
          setState(() {
            _candidates = unique;
            _loading = false;
          });
          _armAutoBackTimer();
          return;
        }
      }

      setState(() {
        _candidates = const [];
        _results = results;
        _loading = false;
      });
      _armAutoBackTimer();
    } catch (e) {
      debugPrint('Load results failed: $e');
      setState(() {
        _error = '$e';
        _loading = false;
      });
      _armAutoBackTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final raceTheme = _theme;
    final cs = Theme.of(context).colorScheme;
    final appState = context.watch<RsuAppState>();
    final isKioskMode = appState.logoutCode != null && appState.logoutCode!.isNotEmpty;

    final background = raceTheme == null ? null : _colorFromHex(raceTheme.backgroundColorHex);

    return PopScope(
      canPop: !isKioskMode,
      child: Listener(
        onPointerDown: (_) => _armAutoBackTimer(),
        onPointerMove: (_) => _armAutoBackTimer(),
        child: Scaffold(
        backgroundColor: background ?? Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: null,
          leading: IconButton(
            onPressed: () => context.go('${AppRoutes.search}?raceId=${widget.raceId}'),
            icon: Icon(Icons.arrow_back, color: cs.primary),
          ),
          actions: const [LogoutActionButton()],
        ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: CopyableErrorPanel(message: _error!, title: 'Load results failed'),
                  )
                : _candidates.isNotEmpty
                    ? Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: CandidatePickerPanel(
                              candidates: _candidates,
                              onPick: (bib) => context.go('${AppRoutes.results}?raceId=${widget.raceId}&searchType=bib&bib=$bib'),
                              onCancel: () => context.pop(),
                            ),
                          ),
                        ),
                      )
                    : ResultsLegacyLikeView(race: _race, theme: raceTheme, results: _results, onTapName: () => context.go('${AppRoutes.search}?raceId=${widget.raceId}')),
      ),
    ),
    ),
    );
  }

  static RsuEventResult _parseEventResult({required String eventName, required Map<String, dynamic> row, required Map<String, dynamic> setMap, required String chipTime, required String bib}) {
    final headers = (setMap['results_headers'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final divisionFinishers = (setMap['num_division_finishers'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

    String divisionLabel = '';
    String divisionPlace = '';
    int divisionFinishersCount = 0;
    int genderFinishersCount = 0;

    final gender = '${row['gender'] ?? ''}';

    int? matchedDivisionFinishers;

    for (final entry in divisionFinishers.entries) {
      final did = entry.key;
      final dpi = 'division-$did-placement';
      final placementVal = row[dpi];
      final header = '${headers[dpi] ?? ''}'.trim();
      final finishersForThisDivision = (entry.value is int) ? entry.value as int : int.tryParse('${entry.value ?? 0}') ?? 0;

      if (placementVal != null && '$placementVal'.trim().isNotEmpty) {
        divisionPlace = '$placementVal'.trim();
        matchedDivisionFinishers = finishersForThisDivision;
        if (divisionLabel.isEmpty && header.isNotEmpty) {
          divisionLabel = header;
        }
      }

      if (gender.isNotEmpty && header.contains(gender) && !header.contains('Overall')) {
        genderFinishersCount += finishersForThisDivision;
      }
    }

    // Prefer the finishers count for the division that actually produced a placement.
    // If we can't match one, fall back to the first entry (better than showing 0).
    if (matchedDivisionFinishers != null) {
      divisionFinishersCount = matchedDivisionFinishers;
    } else if (divisionFinishers.isNotEmpty) {
      final firstVal = divisionFinishers.values.first;
      divisionFinishersCount = (firstVal is int) ? firstVal : int.tryParse('${firstVal ?? 0}') ?? 0;
    }

    String genderPlace = '';
    try {
      final genderHeaderEntry = headers.entries.whereType<MapEntry<String, dynamic>>().cast<MapEntry<String, dynamic>>().firstWhere(
        (e) => '${e.value}'.trim().toLowerCase() == 'gender place',
        orElse: () => const MapEntry<String, dynamic>('', ''),
      );
      final genderKey = genderHeaderEntry.key;
      if (genderKey.isNotEmpty) {
        genderPlace = '${row[genderKey] ?? ''}'.trim();
      }
    } catch (_) {
      // Ignore and fall back.
    }

    // Fallbacks seen in some RSU payloads.
    if (genderPlace.isEmpty) {
      for (final k in const ['gender_place', 'gender-place', 'gender_placement', 'gender-placement']) {
        final v = row[k];
        if (v != null && '$v'.trim().isNotEmpty) {
          genderPlace = '$v'.trim();
          break;
        }
      }
    }

    final numFinishers = (setMap['num_finishers'] is int) ? setMap['num_finishers'] as int : int.tryParse('${setMap['num_finishers'] ?? 0}') ?? 0;

    return RsuEventResult(
      eventName: eventName,
      bib: bib,
      firstName: '${row['first_name'] ?? ''}'.toUpperCase(),
      lastName: '${row['last_name'] ?? ''}'.toUpperCase(),
      chipTime: chipTime.split('.').first,
      pace: '${row['pace'] ?? ''}',
      place: '${row['place'] ?? ''}',
      divisionLabel: divisionLabel,
      divisionPlace: divisionPlace,
      genderPlace: genderPlace,
      finishers: numFinishers,
      genderFinishers: genderFinishersCount,
      divisionFinishers: divisionFinishersCount,
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

class CandidatePickerPanel extends StatelessWidget {
  final List<RsuCandidate> candidates;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  const CandidatePickerPanel({super.key, required this.candidates, required this.onPick, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Select participant', style: Theme.of(context).textTheme.titleLarge)),
                TextButton(onPressed: onCancel, child: Text('Cancel', style: TextStyle(color: cs.primary))),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 520,
              child: ListView.separated(
                itemCount: candidates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final c = candidates[i];
                  return InkWell(
                    onTap: () => onPick(c.bib),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
                        color: cs.surface,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.displayName, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text('${c.event} • ${c.city}${c.state.isEmpty ? '' : ', ${c.state}'}', style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), color: cs.primaryContainer),
                            child: Text('Bib ${c.bib}', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onPrimaryContainer)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultsLegacyLikeView extends StatefulWidget {
  final RsuRaceDetails? race;
  final RsuRaceThemeSettings? theme;
  final List<RsuEventResult> results;
  final VoidCallback onTapName;

  const ResultsLegacyLikeView({super.key, required this.race, required this.theme, required this.results, required this.onTapName});

  @override
  State<ResultsLegacyLikeView> createState() => _ResultsLegacyLikeViewState();
}

class _ResultsLegacyLikeViewState extends State<ResultsLegacyLikeView> {
  static String _normalizeRemoteImageUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('http://')) return 'https://${u.substring('http://'.length)}';
    if (u.startsWith('/')) return 'https://runsignup.com$u';
    if (!u.startsWith('http://') && !u.startsWith('https://')) return 'https://runsignup.com/$u';
    return u;
  }
  int _selected = 0;

  @override
  void didUpdateWidget(covariant ResultsLegacyLikeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected >= widget.results.length) {
      _selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final labelColor = _colorFromHex(widget.theme?.labelColorHex ?? '') ?? cs.primary;
    final dataColor = _colorFromHex(widget.theme?.dataColorHex ?? '') ?? cs.tertiary;
    final nameColor = _colorFromHex(widget.theme?.nameColorHex ?? '') ?? cs.onSurface;

    final rawRaceLogoUrl = widget.race?.logoUrl ?? '';
    final raceLogoUrl = _normalizeRemoteImageUrl(rawRaceLogoUrl);
    if (rawRaceLogoUrl.trim().isEmpty) {
      debugPrint('Results header: race.logoUrl is empty (raceId=${widget.race?.raceId ?? '-'})');
    } else {
      debugPrint('Results header: race.logoUrl="$rawRaceLogoUrl" normalized="$raceLogoUrl"');
    }

    final sponsorDataUrl = widget.theme?.sponsorLogoDataUrl ?? '';
    final sponsorBytes = _tryDecodeDataUrlBase64(sponsorDataUrl);

    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final scale = (width / 420.0).clamp(0.82, 1.25);

    if (widget.results.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: RemoteLogoImage(url: raceLogoUrl, height: 72),
                      ),
                    ),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(999)),
                      child: Icon(Icons.error_outline, color: cs.onErrorContainer, size: 36),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No Results Found',
                      style: buildRaceTextStyle(
                        widget.theme?.emptyStateTitleStyle ?? RsuRaceTypographyDefaults.emptyStateTitle,
                        color: cs.onSurface,
                        scale: scale,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('We couldn’t find results for that bib/name for this event. Please verify the search and try again.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: widget.onTapName,
                          icon: Icon(Icons.arrow_back, color: cs.onPrimary),
                          label: Text('Back to Search', style: TextStyle(color: cs.onPrimary)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final selectedResult = widget.results[_selected];
    final typo = widget.theme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _HoverScale(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: RemoteLogoImage(url: raceLogoUrl, height: 110),
                      ),
                    ),
                    if (sponsorBytes != null)
                      _HoverScale(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(sponsorBytes, height: 86, fit: BoxFit.contain),
                        ),
                      ),
                  ],
                ),
              ),

              if (widget.results.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < widget.results.length; i++)
                        ChoiceChip(
                          label: Text(widget.results[i].eventName, overflow: TextOverflow.ellipsis),
                          selected: i == _selected,
                          onSelected: (v) {
                            if (!v) return;
                            setState(() => _selected = i);
                          },
                        ),
                    ],
                  ),
                ),

              GestureDetector(
                onTap: widget.onTapName,
                child: Semantics(
                  button: true,
                  label: 'Runner name. Tap to return to search.',
                  child: _OutlinedDisplayText(
                    text: '${selectedResult.firstName} ${selectedResult.lastName}'.trim(),
                    fill: nameColor,
                    stroke: Colors.white,
                    style: buildRaceTextStyle(
                      typo?.participantNameStyle ?? RsuRaceTypographyDefaults.participantName,
                      color: nameColor,
                      scale: scale,
                    ),
                    textAlign: TextAlign.center,
                    strokeWidth: 2,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Text(
                selectedResult.chipTime.isEmpty ? '-' : selectedResult.chipTime,
                style: buildRaceTextStyle(typo?.chipTimeStyle ?? RsuRaceTypographyDefaults.chipTime, color: dataColor, scale: scale),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              Text(
                '${selectedResult.eventName} FINISHER',
                style: buildRaceTextStyle(typo?.finisherLineStyle ?? RsuRaceTypographyDefaults.finisherLine, color: dataColor, scale: scale),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),

              ResultsMetricSection(theme: typo, label: 'BIB NUMBER', value: selectedResult.bib.isEmpty ? '-' : selectedResult.bib, labelColor: labelColor, dataColor: dataColor, scale: scale),
              const SizedBox(height: 18),

              ResultsMetricSection(theme: typo, label: 'OVERALL RANK', value: _formatRank(selectedResult.place, selectedResult.finishers), labelColor: labelColor, dataColor: dataColor, scale: scale),
              const SizedBox(height: 18),

              if (selectedResult.genderPlace.isNotEmpty) ...[
                ResultsMetricSection(theme: typo, label: 'GENDER RANK', value: _formatRank(selectedResult.genderPlace, selectedResult.genderFinishers), labelColor: labelColor, dataColor: dataColor, scale: scale),
                const SizedBox(height: 18),
              ],

              if (selectedResult.divisionPlace.isNotEmpty && selectedResult.divisionFinishers > 0) ...[
                ResultsMetricSection(
                  theme: typo,
                  label: (selectedResult.divisionLabel.trim().isEmpty
                          ? 'DIVISION RANK'
                          : rsuAgeGroupDisplayLabel(selectedResult.divisionLabel))
                      .trim()
                      .toUpperCase(),
                  value: _formatRank(selectedResult.divisionPlace, selectedResult.divisionFinishers),
                  labelColor: labelColor,
                  dataColor: dataColor,
                  scale: scale,
                ),
                const SizedBox(height: 18),
              ],


              ResultsMetricSection(theme: typo, label: 'AVERAGE PACE', value: selectedResult.pace.isEmpty ? '-' : selectedResult.pace, labelColor: labelColor, dataColor: dataColor, scale: scale),
              const SizedBox(height: 24),

              // Keep the screen clean like the legacy display: no extra cards here.
              // Sharing can be added later if you want parity with the PHP mobile-only share buttons.
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRank(String place, int total) {
    final p = place.trim().isEmpty ? '-' : place.trim();
    if (p == '-' || total <= 0) return p;
    return '$p of $total';
  }

  static Color? _colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return null;
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  static Uint8List? _tryDecodeDataUrlBase64(String dataUrl) {
    if (dataUrl.trim().isEmpty) return null;
    try {
      final comma = dataUrl.indexOf(',');
      final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
      return Uint8List.fromList(const Base64Decoder().convert(b64));
    } catch (e) {
      debugPrint('Failed to decode sponsor logo data url: $e');
      return null;
    }
  }
}

class ResultsMetricSection extends StatelessWidget {
  final RsuRaceThemeSettings? theme;
  final String label;
  final String value;
  final Color labelColor;
  final Color dataColor;
  final double scale;

  const ResultsMetricSection({
    super.key,
    this.theme,
    required this.label,
    required this.value,
    required this.labelColor,
    required this.dataColor,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: buildRaceTextStyle(theme?.metricLabelStyle ?? RsuRaceTypographyDefaults.metricLabel, color: labelColor, scale: scale),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: buildRaceTextStyle(theme?.metricValueStyle ?? RsuRaceTypographyDefaults.metricValue, color: dataColor, scale: scale),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _OutlinedDisplayText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color stroke;
  final Color fill;
  final TextAlign textAlign;
  final double strokeWidth;

  const _OutlinedDisplayText({required this.text, required this.style, required this.stroke, required this.fill, required this.textAlign, required this.strokeWidth});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          textAlign: textAlign,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = stroke,
          ),
        ),
        Text(text, textAlign: textAlign, style: style.copyWith(color: fill)),
      ],
    );
  }
}

class _HoverScale extends StatefulWidget {
  final Widget child;

  const _HoverScale({required this.child});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final targetScale = _hovered ? 1.04 : 1.0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: targetScale,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
