import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class RsuPublicConfig {
  final String? oauthClientId;
  final String? oauthRedirectUri;
  final String? oauthScope;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RsuPublicConfig({this.oauthClientId, this.oauthRedirectUri, this.oauthScope, this.createdAt, this.updatedAt});

  factory RsuPublicConfig.fromJson(Map<String, dynamic> json) {
    String? s(dynamic v) {
      final raw = (v ?? '').toString().trim();
      return raw.isEmpty ? null : raw;
    }

    DateTime? ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final clientId = s(json['oauth_client_id']) ?? s(json['client_id']) ?? s(json['clientId']);
    final redirectUri = s(json['oauth_redirect_uri']) ?? s(json['redirect_uri']) ?? s(json['redirectUri']);
    final scope = s(json['oauth_scope']) ?? s(json['scope']);

    return RsuPublicConfig(
      oauthClientId: clientId,
      oauthRedirectUri: redirectUri,
      oauthScope: scope,
      createdAt: ts(json['createdAt']),
      updatedAt: ts(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'oauth_client_id': oauthClientId,
      'oauth_redirect_uri': oauthRedirectUri,
      'oauth_scope': oauthScope,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    }..removeWhere((k, v) => v == null);
  }
}

class RsuPublicConfigService {
  static const String collectionPath = 'public_config';
  static const String docId = 'rsu';

  final FirebaseFirestore _firestore;
  RsuPublicConfigService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _doc => _firestore.collection(collectionPath).doc(docId);

  /// Loads the shared public configuration from Firestore.
  ///
  /// Returns `null` only when the document does not exist (or has no data).
  /// If the read fails (permission denied / wrong project / network), this throws so callers can
  /// surface a meaningful error instead of claiming the fields are missing.
  Future<RsuPublicConfig?> fetchOnce() async {
    final snap = await _doc.get(const GetOptions(source: Source.serverAndCache));
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return RsuPublicConfig.fromJson(data);
  }

  Future<void> upsertPublicConfig({required String clientId, required String redirectUri, required String scope}) async {
    final now = DateTime.now().toUtc();
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(_doc);
        final existing = snap.data();
        DateTime createdAt;
        final rawCreatedAt = existing == null ? null : existing['createdAt'];
        if (rawCreatedAt is Timestamp) {
          createdAt = rawCreatedAt.toDate();
        } else if (rawCreatedAt is DateTime) {
          createdAt = rawCreatedAt;
        } else if (rawCreatedAt is String) {
          createdAt = DateTime.tryParse(rawCreatedAt) ?? now;
        } else {
          createdAt = now;
        }

        final record = RsuPublicConfig(
          oauthClientId: clientId.trim(),
          oauthRedirectUri: redirectUri.trim(),
          oauthScope: scope.trim(),
          createdAt: createdAt,
          updatedAt: now,
        );

        tx.set(_doc, record.toJson(), SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('Upsert public_config/rsu failed: $e');
      rethrow;
    }
  }
}
