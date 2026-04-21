// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pair_session_model.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/pair_session.dart';

class PairSessionModel extends PairSession {
  const PairSessionModel({
    required super.coupleId,
    required super.user1Uid,
    required super.user1FcmToken,
    required super.user1PublicKeyJson,
    required super.user2Uid,
    required super.user2FcmToken,
    required super.user2PublicKeyJson,
    required super.createdAt,
  });

  factory PairSessionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data()!;
    return PairSessionModel(
      coupleId:           snap.id,
      user1Uid:           d['user1Uid'] as String,
      user1FcmToken:      d['user1FcmToken'] as String,
      user1PublicKeyJson: d['user1PublicKey'] as String,
      user2Uid:           d['user2Uid'] as String,
      user2FcmToken:      d['user2FcmToken'] as String,
      user2PublicKeyJson: d['user2PublicKey'] as String,
      createdAt:          (d['createdAt'] as Timestamp).toDate(),
    );
  }
}
