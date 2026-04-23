import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'rsu_config.dart';

class RsuRaceListDebugInfo {
  final Uri requestUri;
  final Uri effectiveUri;
  final int statusCode;
  final int bodyBytes;
  final String? contentType;
  final String bodySnippet;
  final List<String> topLevelKeys;
  final String racesNodeType;
  final int raceItems;
  final String firstItemType;
  final List<String> firstItemKeys;
  final int parsedRaces;

  const RsuRaceListDebugInfo({
    required this.requestUri,
    required this.effectiveUri,
    required this.statusCode,
    required this.bodyBytes,
    required this.contentType,
    required this.bodySnippet,
    required this.topLevelKeys,
    required this.racesNodeType,
    required this.raceItems,
    required this.firstItemType,
    required this.firstItemKeys,
    required this.parsedRaces,
  });

  String toMultilineString() {
    final b = StringBuffer();
    b.writeln('requestUri: $requestUri');
    b.writeln('effectiveUri: $effectiveUri');
    b.writeln('status: $statusCode');
    b.writeln('contentType: ${contentType ?? '-'}');
    b.writeln('bodyBytes: $bodyBytes');
    b.writeln('topLevelKeys: $topLevelKeys');
    b.writeln('racesNodeType: $racesNodeType');
    b.writeln('raceItems: $raceItems');
    b.writeln('firstItemType: $firstItemType');
    b.writeln('firstItemKeys: $firstItemKeys');
    b.writeln('parsedRaces: $parsedRaces');
    b.writeln('--- bodySnippet (first 2000 chars) ---');
    b.writeln(bodySnippet);
    return b.toString();
  }
}

class RsuRaceListResult {
  final List<RsuRaceSummary> races;
  final RsuRaceListDebugInfo debug;

  const RsuRaceListResult({required this.races, required this.debug});
}

class RsuApi {
  final http.Client _client;

  RsuApi({http.Client? client}) : _client = client ?? http.Client();

  Future<List<RsuRaceSummary>> listRacesWithResults({
    required String accessToken,
    required DateTimeRange range,
    String? timerApiKey,
    String? timerApiSecret,
    bool onlyPartnerRaces = false,
    bool onlyRacesWithResults = true,
  }) async {
    final result = await listRacesWithResultsWithDebug(
      accessToken: accessToken,
      range: range,
      timerApiKey: timerApiKey,
      timerApiSecret: timerApiSecret,
      onlyPartnerRaces: onlyPartnerRaces,
      onlyRacesWithResults: onlyRacesWithResults,
    );
    return result.races;
  }

  Future<RsuRaceListResult> listRacesWithResultsWithDebug({
    required String accessToken,
    required DateTimeRange range,
    String? timerApiKey,
    String? timerApiSecret,
    bool onlyPartnerRaces = false,
    bool onlyRacesWithResults = true,
  }) async {
    final isSingleDay = DateUtils.isSameDay(range.start, range.end);
    final isTodayOnly = isSingleDay && DateUtils.isSameDay(range.start, DateTime.now());

    // Note: We no longer hard-block "partner-only" listing on missing Timer credentials.
    // The upstream API will enforce access restrictions based on provided credentials.

    // Mirror the RunSignup defaults as closely as possible.
    final params = <String, String>{
      'format': 'json',
      'events': 'F',
      'race_headings': 'F',
      'race_links': 'F',
      'include_waiver': 'F',
      'include_multiple_waivers': 'F',
      'include_event_days': 'F',
      'include_extra_date_info': 'F',
      'include_giveaway_details': 'F',
      'page': '1',
      'results_per_page': '50',
      'sort': 'name ASC',
      'distance_units': 'K',
      'search_start_date_only': 'F',
      'start_date': isTodayOnly ? 'today' : _yyyyMmDd(range.start),
      'end_date': isTodayOnly ? 'today' : _yyyyMmDd(range.end),
    };

    if (onlyRacesWithResults) params['only_races_with_results'] = 'T';

    if (onlyPartnerRaces) params['only_partner_races'] = 'T';

    final apiKey = (timerApiKey ?? '').trim();
    if (apiKey.isNotEmpty) params['rsu_api_key'] = apiKey;

    final uri = Uri.parse('${RsuConfig.endpointBase}races').replace(queryParameters: params);

    debugPrint('RSU listRacesWithResults → $uri');

    final get = await _safeGetWithEffectiveUri(uri, accessToken: accessToken, timerApiSecret: timerApiSecret);
    final resp = get.resp;
    debugPrint('RSU listRacesWithResults ← HTTP ${resp.statusCode} (${resp.bodyBytes.length} bytes)');

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    final bodySnippet = bodyText.length <= 2000 ? bodyText : bodyText.substring(0, 2000);

    if (resp.statusCode != 200) {
      final debug = RsuRaceListDebugInfo(
        requestUri: uri,
        effectiveUri: get.effectiveUri,
        statusCode: resp.statusCode,
        bodyBytes: resp.bodyBytes.length,
        contentType: resp.headers['content-type'],
        bodySnippet: bodySnippet,
        topLevelKeys: const [],
        racesNodeType: 'n/a',
        raceItems: 0,
        firstItemType: 'n/a',
        firstItemKeys: const [],
        parsedRaces: 0,
      );
      throw Exception('Failed to list races (HTTP ${resp.statusCode})\n${debug.toMultilineString()}');
    }

    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) {
      final debug = RsuRaceListDebugInfo(
        requestUri: uri,
        effectiveUri: get.effectiveUri,
        statusCode: resp.statusCode,
        bodyBytes: resp.bodyBytes.length,
        contentType: resp.headers['content-type'],
        bodySnippet: bodySnippet,
        topLevelKeys: const [],
        racesNodeType: decoded.runtimeType.toString(),
        raceItems: 0,
        firstItemType: 'n/a',
        firstItemKeys: const [],
        parsedRaces: 0,
      );
      throw Exception('Unexpected response type\n${debug.toMultilineString()}');
    }

    final racesNode = decoded['races'];
    List<dynamic> raceItems = const [];
    if (racesNode is List) {
      raceItems = racesNode;
    } else if (racesNode is Map) {
      final inner = racesNode['race'];
      if (inner is List) {
        raceItems = inner;
      } else if (inner is Map) {
        raceItems = [inner];
      }
    }

    final first = raceItems.isNotEmpty ? raceItems.first : null;
    final firstItemType = first == null ? 'n/a' : first.runtimeType.toString();
    final firstItemKeys = (first is Map) ? first.keys.map((e) => '$e').toList(growable: false) : const <String>[];

    final parsed =
        raceItems.whereType<Map>().map((e) => RsuRaceSummary.fromJson(e.cast<String, dynamic>())).where((r) => r.raceId.isNotEmpty).toList(growable: false);

    final debug = RsuRaceListDebugInfo(
      requestUri: uri,
      effectiveUri: get.effectiveUri,
      statusCode: resp.statusCode,
      bodyBytes: resp.bodyBytes.length,
      contentType: resp.headers['content-type'],
      bodySnippet: bodySnippet,
      topLevelKeys: decoded.keys.map((e) => '$e').toList(growable: false),
      racesNodeType: racesNode == null ? 'null' : racesNode.runtimeType.toString(),
      raceItems: raceItems.length,
      firstItemType: firstItemType,
      firstItemKeys: firstItemKeys,
      parsedRaces: parsed.length,
    );

    debugPrint('RSU listRacesWithResults parsed races=${parsed.length}');
    return RsuRaceListResult(races: parsed, debug: debug);
  }

  Future<({String userId, String email, String firstName, String lastName})> getCurrentUser({required String accessToken, String? timerApiSecret}) async {
    final uri = Uri.parse('${RsuConfig.endpointBase}user/').replace(queryParameters: const {'format': 'json'});
    final resp = await _safeGet(uri, accessToken: accessToken, timerApiSecret: timerApiSecret);
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch current user (HTTP ${resp.statusCode}): ${resp.body}\nURL: $uri');
    }

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
    if (decoded is! Map) throw Exception('Unexpected /user response\nURL: $uri');

    final userNode = (decoded['user'] is Map) ? (decoded['user'] as Map).cast<String, dynamic>() : decoded.cast<String, dynamic>();
    final userId = '${userNode['user_id'] ?? userNode['id'] ?? ''}'.trim();
    final email = '${userNode['email'] ?? ''}'.trim();
    final firstName = '${userNode['first_name'] ?? userNode['firstname'] ?? ''}'.trim();
    final lastName = '${userNode['last_name'] ?? userNode['lastname'] ?? ''}'.trim();

    if (userId.isEmpty) throw Exception('Could not parse user_id from /Rest/user response');
    return (userId: userId, email: email, firstName: firstName, lastName: lastName);
  }

  Future<RsuRaceDetails> getRace({required String accessToken, required String raceId, String? timerApiKey, String? timerApiSecret, String? bibNum, String? lastName}) async {
    final params = <String, String>{'format': 'json', 'most_recent_events_only': 'F', 'include_division_finishers': 'T', 'include_total_finishers': 'T'};
    final apiKey = (timerApiKey ?? '').trim();
    if (apiKey.isNotEmpty) params['rsu_api_key'] = apiKey;
    if (bibNum != null && bibNum.isNotEmpty) params['bib_num'] = bibNum;
    if (lastName != null && lastName.isNotEmpty) params['last_name'] = lastName;

    final uri = Uri.parse('${RsuConfig.endpointBase}race/$raceId').replace(queryParameters: params);
    final resp = await _safeGet(uri, accessToken: accessToken, timerApiSecret: timerApiSecret);
    if (resp.statusCode != 200) {
      throw Exception('Failed to get race (HTTP ${resp.statusCode}): ${resp.body}\nURL: $uri');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) throw Exception('Unexpected response\nURL: $uri');
    return RsuRaceDetails.fromJson(decoded.cast<String, dynamic>());
  }

  Future<Map<String, dynamic>> getEventResults({
    required String accessToken,
    required String raceId,
    required String eventId,
    required Map<String, String> baseParams,
    String? timerApiKey,
    String? timerApiSecret,
  }) async {
    final params = <String, String>{'format': 'json', ...baseParams, 'event_id': eventId};
    final apiKey = (timerApiKey ?? '').trim();
    if (apiKey.isNotEmpty) params['rsu_api_key'] = apiKey;
    final uri = Uri.parse('${RsuConfig.endpointBase}race/$raceId/results/get-results').replace(queryParameters: params);
    final resp = await _safeGet(uri, accessToken: accessToken, timerApiSecret: timerApiSecret);
    if (resp.statusCode != 200) {
      throw Exception('Failed to get results (HTTP ${resp.statusCode}): ${resp.body}\nURL: $uri');
    }
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) throw Exception('Unexpected response\nURL: $uri');
    return decoded.cast<String, dynamic>();
  }

  Future<({http.Response resp, Uri effectiveUri})> _safeGetWithEffectiveUri(Uri uri, {required String accessToken, String? timerApiSecret}) async {
    try {
      final effectiveUri = kIsWeb ? _toFirebaseProxyUri(uri) : uri;
      final headers = <String, String>{'Authorization': 'Bearer $accessToken'};
      final secret = (timerApiSecret ?? '').trim();
      if (secret.isNotEmpty) headers['X-RSU-API-SECRET'] = secret;
      final resp = await _client.get(effectiveUri, headers: headers).timeout(const Duration(seconds: 30));
      return (resp: resp, effectiveUri: effectiveUri);
    } on TimeoutException {
      throw Exception('Request timed out after 30 seconds\nURL: $uri');
    } on http.ClientException catch (e) {
      throw Exception(_describeClientException(e, uri));
    } catch (e) {
      throw Exception('Request failed: $e\nURL: $uri');
    }
  }

  Future<http.Response> _safeGet(Uri uri, {required String accessToken, String? timerApiSecret}) async {
    final r = await _safeGetWithEffectiveUri(uri, accessToken: accessToken, timerApiSecret: timerApiSecret);
    return r.resp;
  }

  Uri _toFirebaseProxyUri(Uri target) {
    final projectId = Firebase.app().options.projectId;
    final proxyBase = RsuConfig.firebaseFunctionsProxyBase(projectId: projectId);
    return Uri.parse(proxyBase).replace(queryParameters: {'url': target.toString()});
  }

  String _describeClientException(http.ClientException e, Uri uri) {
    final msg = e.toString();
    if (kIsWeb && msg.contains('Failed to fetch')) {
      return [
        'Network request failed in the browser (ClientException: Failed to fetch).',
        'URL: $uri',
        '',
        'This usually means the browser blocked the call (CORS), or a network policy/extension blocked it.',
        'Because this app is running on https://*.share.dreamflow.app, the RunSignup REST API must allow cross-origin requests from that origin—many endpoints do not.',
        '',
        'Fix options:',
        '1) Add a small proxy (Firebase Cloud Function or Supabase Edge Function) that calls RunSignup server-side and adds CORS headers.',
        '2) Run the app as a native Android/iOS build (no browser CORS).',
      ].join('\n');
    }
    return 'Network request failed: $msg\nURL: $uri';
  }

  static String _yyyyMmDd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
