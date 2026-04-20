import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:rsu_results/rsu/timer_account.dart';

class RsuTimerAccountService {
  static const collectionPath = 'rsu_timer_accounts';

  final FirebaseFirestore _db;
  final http.Client _client;

  RsuTimerAccountService({FirebaseFirestore? db, http.Client? client}) : _db = db ?? FirebaseFirestore.instance, _client = client ?? http.Client();

  Uri _functionUrl({String region = 'us-central1', required String functionName}) {
    final app = Firebase.app();
    final projectId = (app.options.projectId ?? '').trim();
    if (projectId.isEmpty) throw Exception('Missing Firebase projectId (Firebase not configured?)');
    return Uri.parse('https://$region-$projectId.cloudfunctions.net/$functionName');
  }

  /// New canonical storage key: Firebase Auth uid.
  ///
  /// Using Firebase uid avoids blocking writes when we have a Firebase session but
  /// have not yet hydrated/persisted the RunSignup identity (rsuUserId).
  DocumentReference<Map<String, dynamic>> _docByFirebaseUid(String firebaseUid) => _db.collection(collectionPath).doc(firebaseUid);

  /// Legacy storage key: RunSignup user id.
  DocumentReference<Map<String, dynamic>> _docByRsuUserId(String rsuUserId) => _db.collection(collectionPath).doc(rsuUserId);

  Future<RsuTimerAccount?> getAccountByFirebaseUid(String firebaseUid) async {
    final uid = firebaseUid.trim();
    if (uid.isEmpty) return null;
    final snap = await _docByFirebaseUid(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return RsuTimerAccount.fromJson(data);
  }

  /// Privileged fetch via Cloud Function (admin SDK) for cases where Firestore rules
  /// intentionally deny direct client reads.
  Future<RsuTimerAccount?> getAccountByFirebaseUidViaFunction({required String idToken}) async {
    final t = idToken.trim();
    if (t.isEmpty) throw Exception('Missing Firebase ID token');

    final uri = _functionUrl(functionName: 'rsuGetTimerAccount');
    final resp = await _client.post(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $t',
    }, body: jsonEncode({}));

    final bodyText = utf8.decode(resp.bodyBytes, allowMalformed: true);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      debugPrint('rsuGetTimerAccount failed HTTP ${resp.statusCode}: $bodyText');
      throw Exception('rsuGetTimerAccount failed (HTTP ${resp.statusCode}). Body: ${bodyText.isEmpty ? '<empty>' : bodyText}');
    }

    final decoded = jsonDecode(bodyText);
    if (decoded is! Map) throw Exception('Unexpected rsuGetTimerAccount response');

    final acct = decoded['timerAccount'];
    if (acct is! Map) return null;
    return RsuTimerAccount.fromJson(acct.cast<String, dynamic>());
  }

  Future<RsuTimerAccount?> getAccountByFirebaseUidSafe(String firebaseUid) async {
    try {
      return await getAccountByFirebaseUid(firebaseUid);
    } catch (e) {
      debugPrint('getAccountByFirebaseUid failed: $e');
      return null;
    }
  }

  Future<RsuTimerAccount?> getAccount(String rsuUserId) async {
    final snap = await _docByRsuUserId(rsuUserId).get();
    final data = snap.data();
    if (data == null) return null;
    return RsuTimerAccount.fromJson(data);
  }

  Future<RsuTimerAccount?> getAccountSafe(String rsuUserId) async {
    try {
      return await getAccount(rsuUserId);
    } catch (e) {
      debugPrint('getAccount failed: $e');
      return null;
    }
  }

  Stream<RsuTimerAccount?> watchAccount(String rsuUserId) {
    return _docByRsuUserId(rsuUserId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      try {
        return RsuTimerAccount.fromJson(data);
      } catch (e) {
        debugPrint('watchAccount decode failed: $e');
        return null;
      }
    });
  }

  Future<void> upsertAccount({
    required String firebaseUid,
    String? rsuUserId,
    String? email,
    String? firstName,
    String? lastName,
    required String timerApiKey,
    required String timerApiSecret,
  }) async {
    // IMPORTANT (web + rules): Firestore transactions require read access to the target document.
    // If rules allow write but not read (common for secrets), a transaction will fail even though
    // a plain set() would succeed. So we avoid runTransaction here.
    final now = DateTime.now().toUtc();
    final uid = firebaseUid.trim();
    if (uid.isEmpty) throw ArgumentError('firebaseUid is empty');

    final normalizedRsuUserId = (rsuUserId ?? '').trim();
    final normalizedEmail = (email ?? '').trim();
    final normalizedFirst = (firstName ?? '').trim();
    final normalizedLast = (lastName ?? '').trim();

    final record = RsuTimerAccount(
      rsuUserId: normalizedRsuUserId,
      email: normalizedEmail,
      firstName: normalizedFirst,
      lastName: normalizedLast,
      timerApiKey: timerApiKey,
      timerApiSecret: timerApiSecret,
      createdAt: now,
      updatedAt: now,
    );

    final data = record.toJson();
    data['ownerUid'] = uid;

    try {
      await _docByFirebaseUid(uid).set(data, SetOptions(merge: true));

      // Optional legacy mirror for backwards compatibility (older builds keyed by rsuUserId).
      // Not atomic with the primary write, but good enough for migration.
      if (normalizedRsuUserId.isNotEmpty && normalizedRsuUserId != uid) {
        await _docByRsuUserId(normalizedRsuUserId).set(data, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('upsertAccount failed: $e');
      rethrow;
    }
  }

  DateTime? _readTimestamp(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
