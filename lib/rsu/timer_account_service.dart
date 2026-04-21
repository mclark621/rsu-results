import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:rsu_results/rsu/timer_account.dart';

class RsuTimerAccountService {
  static const collectionPath = 'rsu_timer_accounts';

  final FirebaseFirestore _db;

  RsuTimerAccountService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

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
    try {
      final snap = await _docByFirebaseUid(uid).get();
      final data = snap.data();
      if (data == null) return null;
      return RsuTimerAccount.fromJson(data);
    } catch (e) {
      debugPrint('getAccountByFirebaseUid failed: $e');
      return null;
    }
  }

  Future<RsuTimerAccount?> getAccount(String rsuUserId) async {
    try {
      final snap = await _docByRsuUserId(rsuUserId).get();
      final data = snap.data();
      if (data == null) return null;
      return RsuTimerAccount.fromJson(data);
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
