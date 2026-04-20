import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RsuFirebaseAuthService {
  final http.Client _client;

  RsuFirebaseAuthService({http.Client? client}) : _client = client ?? http.Client();

  Uri _functionUrl({String region = 'us-central1'}) {
    final app = Firebase.app();
    final projectId = (app.options.projectId ?? '').trim();
    if (projectId.isEmpty) throw Exception('Missing Firebase projectId (Firebase not configured?)');
    return Uri.parse('https://$region-$projectId.cloudfunctions.net/rsuFirebaseLogin');
  }

  Future<({String firebaseCustomToken, String rsuUserId, String email, String firstName, String lastName})> mintCustomToken({required String rsuAccessToken}) async {
    final t = rsuAccessToken.trim();
    if (t.isEmpty) throw Exception('Missing RunSignup access token');

    final uri = _functionUrl();
    final resp = await _client.post(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $t',
    });

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode != 200) {
      debugPrint('rsuFirebaseLogin failed HTTP ${resp.statusCode}: $bodyText');
      throw Exception('rsuFirebaseLogin failed (HTTP ${resp.statusCode}). Body: ${bodyText.isEmpty ? '<empty>' : bodyText}');
    }

    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) throw Exception('Unexpected rsuFirebaseLogin response');

    final token = '${decoded['firebaseCustomToken'] ?? ''}'.trim();
    final user = decoded['rsuUser'];
    final userMap = (user is Map) ? user.cast<String, dynamic>() : <String, dynamic>{};
    final userId = '${userMap['userId'] ?? ''}'.trim();
    final email = '${userMap['email'] ?? ''}'.trim();
    final firstName = '${userMap['firstName'] ?? ''}'.trim();
    final lastName = '${userMap['lastName'] ?? ''}'.trim();

    if (token.isEmpty || userId.isEmpty) throw Exception('Missing firebaseCustomToken or rsuUserId from rsuFirebaseLogin');
    return (firebaseCustomToken: token, rsuUserId: userId, email: email, firstName: firstName, lastName: lastName);
  }

  Future<({UserCredential credential, String rsuUserId, String email, String firstName, String lastName})> signInWithRsuAccessToken({required String rsuAccessToken}) async {
    final minted = await mintCustomToken(rsuAccessToken: rsuAccessToken);
    final cred = await FirebaseAuth.instance.signInWithCustomToken(minted.firebaseCustomToken);
    return (credential: cred, rsuUserId: minted.rsuUserId, email: minted.email, firstName: minted.firstName, lastName: minted.lastName);
  }
}
