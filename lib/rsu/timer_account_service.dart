import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:rsu_results/rsu/timer_account.dart';

class RsuTimerAccountService {
  static const collectionPath = 'rsu_timer_accounts';

  final FirebaseFirestore _db;

  RsuTimerAccountService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// **PRIMARY PATH**: users/{uid}/rsu_timer_account/current
  /// This is where the data actually lives based on the Firestore structure.
  DocumentReference<Map<String, dynamic>> _userSubcollectionDoc(String uid) =>
      _db.collection('users').doc(uid).collection('rsu_timer_account').doc('current');

  /// New canonical storage key: Firebase Auth uid.
  ///
  /// Using Firebase uid avoids blocking writes when we have a Firebase session but
  /// have not yet hydrated/persisted the RunSignup identity (rsuUserId).
  DocumentReference<Map<String, dynamic>> _docByFirebaseUid(String firebaseUid) => _db.collection(collectionPath).doc(firebaseUid);

  /// Legacy storage key: RunSignup user id.
  DocumentReference<Map<String, dynamic>> _docByRsuUserId(String rsuUserId) => _db.collection(collectionPath).doc(rsuUserId);

  Future<RsuTimerAccount?> getAccountByFirebaseUid(String firebaseUid) async {
    final uid = firebaseUid.trim();
    debugPrint('TimerAccountService.getAccountByFirebaseUid: uid=$uid');
    if (uid.isEmpty) {
      debugPrint('TimerAccountService.getAccountByFirebaseUid: uid is empty, returning null');
      return null;
    }

    // **PRIMARY**: Check users/{uid}/rsu_timer_account/current FIRST
    try {
      final subcollectionRef = _userSubcollectionDoc(uid);
      debugPrint('TimerAccountService: checking PRIMARY path: ${subcollectionRef.path}');
      final subcollectionSnap = await subcollectionRef.get();
      debugPrint('TimerAccountService: PRIMARY path doc exists=${subcollectionSnap.exists}');
      if (subcollectionSnap.exists) {
        final data = subcollectionSnap.data();
        if (data != null) {
          debugPrint('TimerAccountService: PRIMARY path data keys=${data.keys.toList()}');
          final acct = _parseAccountWithAlternativeFieldNames(data);
          if (acct != null && acct.timerApiKey.isNotEmpty && acct.timerApiSecret.isNotEmpty) {
            debugPrint('TimerAccountService: FOUND at PRIMARY path!');
            return acct;
          }
        }
      }
    } catch (e) {
      debugPrint('TimerAccountService: PRIMARY path lookup failed: $e');
    }

    // **FALLBACK**: Check legacy rsu_timer_accounts/{uid}
    try {
      final docRef = _docByFirebaseUid(uid);
      debugPrint('TimerAccountService.getAccountByFirebaseUid: fetching FALLBACK doc at ${docRef.path}');
      final snap = await docRef.get();
      debugPrint('TimerAccountService.getAccountByFirebaseUid: FALLBACK doc exists=${snap.exists}');
      final data = snap.data();
      if (data == null) {
        debugPrint('TimerAccountService.getAccountByFirebaseUid: FALLBACK data is null');
        return null;
      }
      debugPrint('TimerAccountService.getAccountByFirebaseUid: FALLBACK data keys=${data.keys.toList()}');
      // Try standard parsing first, then alternative field names
      final standard = RsuTimerAccount.fromJson(data);
      if (standard.timerApiKey.isNotEmpty && standard.timerApiSecret.isNotEmpty) {
        return standard;
      }
      // Fallback to alternative field name parsing
      debugPrint('TimerAccountService.getAccountByFirebaseUid: standard parse had empty key/secret, trying alternative field names');
      return _parseAccountWithAlternativeFieldNames(data) ?? standard;
    } catch (e) {
      debugPrint('getAccountByFirebaseUid FALLBACK failed: $e');
      return null;
    }
  }

  Future<RsuTimerAccount?> getAccount(String rsuUserId) async {
    try {
      final docRef = _docByRsuUserId(rsuUserId);
      debugPrint('TimerAccountService.getAccount: fetching doc at ${docRef.path}');
      final snap = await docRef.get();
      debugPrint('TimerAccountService.getAccount: doc exists=${snap.exists}');
      final data = snap.data();
      if (data == null) {
        debugPrint('TimerAccountService.getAccount: data is null');
        return null;
      }
      debugPrint('TimerAccountService.getAccount: data keys=${data.keys.toList()}');
      // Try standard parsing first, then alternative field names
      final standard = RsuTimerAccount.fromJson(data);
      if (standard.timerApiKey.isNotEmpty && standard.timerApiSecret.isNotEmpty) {
        return standard;
      }
      debugPrint('TimerAccountService.getAccount: standard parse had empty key/secret, trying alternative field names');
      return _parseAccountWithAlternativeFieldNames(data) ?? standard;
    } catch (e) {
      debugPrint('getAccount failed: $e');
      return null;
    }
  }

  /// Query by rsuUserId FIELD (not document ID). Handles cases where doc ID differs.
  Future<RsuTimerAccount?> getAccountByRsuUserIdField(String rsuUserId) async {
    final id = rsuUserId.trim();
    debugPrint('TimerAccountService.getAccountByRsuUserIdField: rsuUserId=$id');
    if (id.isEmpty) return null;
    try {
      // Try both exact match and numeric match (in case stored as int vs string)
      final query = _db.collection(collectionPath).where('rsuUserId', isEqualTo: id).limit(1);
      debugPrint('TimerAccountService.getAccountByRsuUserIdField: querying where rsuUserId=$id');
      final snap = await query.get();
      debugPrint('TimerAccountService.getAccountByRsuUserIdField: found ${snap.docs.length} docs');
      if (snap.docs.isEmpty) {
        // Try numeric version
        final numericId = int.tryParse(id);
        if (numericId != null) {
          final numQuery = _db.collection(collectionPath).where('rsuUserId', isEqualTo: numericId).limit(1);
          final numSnap = await numQuery.get();
          debugPrint('TimerAccountService.getAccountByRsuUserIdField: numeric query found ${numSnap.docs.length} docs');
          if (numSnap.docs.isNotEmpty) {
            final data = numSnap.docs.first.data();
            debugPrint('TimerAccountService.getAccountByRsuUserIdField: data keys=${data.keys.toList()}');
            return _parseAccountWithAlternativeFieldNames(data);
          }
        }
        return null;
      }
      final data = snap.docs.first.data();
      debugPrint('TimerAccountService.getAccountByRsuUserIdField: data keys=${data.keys.toList()}');
      return _parseAccountWithAlternativeFieldNames(data);
    } catch (e) {
      debugPrint('getAccountByRsuUserIdField failed: $e');
      return null;
    }
  }

  /// Parse account data supporting alternative field name formats (snake_case, etc.)
  RsuTimerAccount? _parseAccountWithAlternativeFieldNames(Map<String, dynamic> data) {
    // Try standard field names first
    String getField(List<String> possibleNames) {
      for (final name in possibleNames) {
        final val = data[name];
        if (val != null) return '$val';
      }
      return '';
    }

    final timerApiKey = getField(['timerApiKey', 'timer_api_key', 'apiKey', 'api_key', 'rsu_api_key']);
    final timerApiSecret = getField(['timerApiSecret', 'timer_api_secret', 'apiSecret', 'api_secret', 'rsu_api_secret']);
    
    debugPrint('_parseAccountWithAlternativeFieldNames: timerApiKey=${timerApiKey.isEmpty ? "EMPTY" : "SET(${timerApiKey.length})"} timerApiSecret=${timerApiSecret.isEmpty ? "EMPTY" : "SET(${timerApiSecret.length})"}');

    if (timerApiKey.isEmpty && timerApiSecret.isEmpty) return null;

    return RsuTimerAccount(
      rsuUserId: getField(['rsuUserId', 'rsu_user_id', 'userId', 'user_id']),
      email: getField(['email']),
      firstName: getField(['firstName', 'first_name']),
      lastName: getField(['lastName', 'last_name']),
      timerApiKey: timerApiKey,
      timerApiSecret: timerApiSecret,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
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
      // **PRIMARY**: Write to users/{uid}/rsu_timer_account/current
      debugPrint('upsertAccount: writing to PRIMARY path: users/$uid/rsu_timer_account/current');
      await _userSubcollectionDoc(uid).set(data, SetOptions(merge: true));

      // Also write to legacy path for backwards compatibility
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
