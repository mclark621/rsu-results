import 'package:cloud_firestore/cloud_firestore.dart';

class RsuTimerAccount {
  final String rsuUserId;
  final String email;
  final String firstName;
  final String lastName;
  final String timerApiKey;
  final String timerApiSecret;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RsuTimerAccount({
    required this.rsuUserId,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.timerApiKey,
    required this.timerApiSecret,
    required this.createdAt,
    required this.updatedAt,
  });

  RsuTimerAccount copyWith({String? email, String? firstName, String? lastName, String? timerApiKey, String? timerApiSecret, DateTime? createdAt, DateTime? updatedAt}) {
    return RsuTimerAccount(
      rsuUserId: rsuUserId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      timerApiKey: timerApiKey ?? this.timerApiKey,
      timerApiSecret: timerApiSecret ?? this.timerApiSecret,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'rsuUserId': rsuUserId,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'timerApiKey': timerApiKey,
    'timerApiSecret': timerApiSecret,
    'createdAt': Timestamp.fromDate(createdAt.toUtc()),
    'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
  };

  factory RsuTimerAccount.fromJson(Map<String, dynamic> json) {
    DateTime readDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return RsuTimerAccount(
      rsuUserId: '${json['rsuUserId'] ?? ''}',
      email: '${json['email'] ?? ''}',
      firstName: '${json['firstName'] ?? ''}',
      lastName: '${json['lastName'] ?? ''}',
      timerApiKey: '${json['timerApiKey'] ?? ''}',
      timerApiSecret: '${json['timerApiSecret'] ?? ''}',
      createdAt: readDate(json['createdAt']),
      updatedAt: readDate(json['updatedAt']),
    );
  }
}
