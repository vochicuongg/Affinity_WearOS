// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pair_session.dart
//  Domain entity for an active couple binding in the `couples` collection.
//  This is the 1-to-1 lock: exactly two devices, their keys, and tokens.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

class PairSession extends Equatable {
  const PairSession({
    required this.coupleId,
    required this.user1Uid,
    required this.user1FcmToken,
    required this.user1PublicKeyJson,
    required this.user2Uid,
    required this.user2FcmToken,
    required this.user2PublicKeyJson,
    required this.createdAt,
  });

  final String coupleId;
  final String user1Uid;
  final String user1FcmToken;
  final String user1PublicKeyJson;
  final String user2Uid;
  final String user2FcmToken;
  final String user2PublicKeyJson;
  final DateTime createdAt;

  /// Returns the FCM token of the partner given the local [uid].
  String partnerFcmToken(String uid) =>
      uid == user1Uid ? user2FcmToken : user1FcmToken;

  /// Returns the partner's RSA public key JSON given the local [uid].
  String partnerPublicKeyJson(String uid) =>
      uid == user1Uid ? user2PublicKeyJson : user1PublicKeyJson;

  @override
  List<Object?> get props => [coupleId, user1Uid, user2Uid];
}
