import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:rsu_results/rsu/timer_account.dart';

class RsuTimerAccountService {
  static const collectionPath = 'rsu_timer_accounts';

  final FirebaseFirestore _db;

  RsuTimerAccountService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String rsuUserId) => _db.collection(collectionPath).doc(rsuUserId);

  Future<RsuTimerAccount?> getAccount(String rsuUserId) async {
    try {
      final snap = await _doc(rsuUserId).get();
      final data = snap.data();
      if (data == null) return null;
      return RsuTimerAccount.fromJson(data);
    } catch (e) {
      debugPrint('getAccount failed: $e');
      return null;
    }
  }

  Stream<RsuTimerAccount?> watchAccount(String rsuUserId) {
    return _doc(rsuUserId).snapshots().map((snap) {
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
    required String rsuUserId,
    required String email,
    required String firstName,
    required String lastName,
    required String timerApiKey,
    required String timerApiSecret,
  }) async {
    final now = DateTime.now().toUtc();
    final doc = _doc(rsuUserId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(doc);
        final existing = snap.data();
        final createdAt = existing == null ? now : _readTimestamp(existing['createdAt']) ?? now;
        final record = RsuTimerAccount(
          rsuUserId: rsuUserId,
          email: email,
          firstName: firstName,
          lastName: lastName,
          timerApiKey: timerApiKey,
          timerApiSecret: timerApiSecret,
          createdAt: createdAt,
          updatedAt: now,
        );
        tx.set(doc, record.toJson(), SetOptions(merge: true));
      });
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
