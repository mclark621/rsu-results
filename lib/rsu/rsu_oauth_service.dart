import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'rsu_config.dart';
import 'web_frame_utils.dart';

class RsuOAuthToken {
  final String accessToken;
  final int expiresIn;
  final String refreshToken;

  const RsuOAuthToken({required this.accessToken, required this.expiresIn, required this.refreshToken});
}

class RsuOAuthService {
  final http.Client _client;

  RsuOAuthService({http.Client? client}) : _client = client ?? http.Client();

  Future<Uri> buildAuthorizationUrl({required String clientId, required String redirectUri, required String scope, required String state, required String codeChallenge}) async {
    debugPrint('OAuth authorize: client_id="$clientId" redirect_uri="$redirectUri" scope="$scope"');
    final params = <String, String>{
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
      'response_type': 'code',
      'scope': scope,
      'state': state,
    };
    return Uri.parse(RsuConfig.authEndpoint).replace(queryParameters: params);
  }

  Future<void> launchAuthorizationUrl(Uri url) async {
    // If we’re running inside Dreamflow’s preview iframe, we must open OAuth in a new tab
    // (top-level browsing context) to avoid X-Frame-Options/CSP refusal.
    //
    // But on a *real deployed web app* (top-level), it’s better UX to keep OAuth in the
    // same tab so the redirect returns to the same app instance.
    final webWindowName = (kIsWeb && WebFrameUtils.isInIFrame) ? '_blank' : '_self';
    final ok = await launchUrl(
      url,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? webWindowName : null,
    );
    if (!ok) throw Exception('Failed to open browser for OAuth');
  }

  /// Exchanges an auth `code` for tokens.
  ///
  /// IMPORTANT: For security, we default to redeeming the code on our Firebase Cloud Function
  /// (`rsuTokenExchange`) which holds the `client_secret` as a Functions secret.
  Future<RsuOAuthToken> exchangeCodeForToken({
    required String clientId,
    required String redirectUri,
    required String codeVerifier,
    required String code,
    bool allowDirectFallback = false,
  }) async {
    // Prefer server-side token exchange so client_secret never exists on-device.
    try {
      return await exchangeCodeForTokenViaFirebase(clientId: clientId, redirectUri: redirectUri, codeVerifier: codeVerifier, code: code);
    } catch (e) {
      debugPrint('OAuth token exchange via Firebase failed: $e');
      if (!allowDirectFallback) {
        throw Exception('Token exchange via Firebase failed: $e');
      }
      debugPrint('Falling back to direct exchange (may fail if client_secret is required).');
      return await exchangeCodeForTokenDirect(clientId: clientId, redirectUri: redirectUri, codeVerifier: codeVerifier, code: code);
    }
  }

  Future<RsuOAuthToken> exchangeCodeForTokenViaFirebase({required String clientId, required String redirectUri, required String codeVerifier, required String code, String region = 'us-central1'}) async {
    final app = Firebase.app();
    final projectId = (app.options.projectId ?? '').trim();
    if (projectId.isEmpty) throw Exception('Missing Firebase projectId (Firebase not configured?)');

    final uri = Uri.parse(RsuConfig.firebaseFunctionsTokenExchangeUrl(projectId: projectId, region: region));
    final resp = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'client_id': clientId, 'redirect_uri': redirectUri, 'code': code, 'code_verifier': codeVerifier}));

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      debugPrint('rsuTokenExchange failed HTTP ${resp.statusCode}: $bodyText');
      throw Exception('Token exchange failed (HTTP ${resp.statusCode}). Body: ${bodyText.isEmpty ? '<empty>' : bodyText}');
    }

    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) throw Exception('Unexpected token response');

    final accessToken = '${decoded['access_token'] ?? ''}';
    final expiresIn = (decoded['expires_in'] is int) ? decoded['expires_in'] as int : int.tryParse('${decoded['expires_in'] ?? ''}') ?? 0;
    final refreshToken = '${decoded['refresh_token'] ?? ''}';

    if (accessToken.isEmpty) throw Exception('No access_token in response');
    return RsuOAuthToken(accessToken: accessToken, expiresIn: expiresIn, refreshToken: refreshToken);
  }

  Future<RsuOAuthToken> exchangeCodeForTokenDirect({required String clientId, required String redirectUri, required String codeVerifier, required String code}) async {
    final body = <String, String>{'grant_type': 'authorization_code', 'client_id': clientId, 'redirect_uri': redirectUri, 'code_verifier': codeVerifier, 'code': code};

    final resp = await _client.post(Uri.parse(RsuConfig.tokenEndpoint), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body);
    if (resp.statusCode != 200) throw Exception('Token exchange failed (HTTP ${resp.statusCode}): ${resp.body}');

    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) throw Exception('Unexpected token response');

    final accessToken = '${decoded['access_token'] ?? ''}';
    final expiresIn = (decoded['expires_in'] is int) ? decoded['expires_in'] as int : int.tryParse('${decoded['expires_in'] ?? ''}') ?? 0;
    final refreshToken = '${decoded['refresh_token'] ?? ''}';

    if (accessToken.isEmpty) throw Exception('No access_token in response');
    return RsuOAuthToken(accessToken: accessToken, expiresIn: expiresIn, refreshToken: refreshToken);
  }

  static String randomUrlSafeString(int bytes) {
    final rnd = Random.secure();
    final data = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }

  static String codeChallengeS256(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes).bytes;
    return base64UrlEncode(digest).replaceAll('=', '');
  }
}
