// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — user_profile_model.dart + pair_session_model.dart
//  Data models: Firestore ↔ domain entity mappings.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/user_profile.dart';

class UserProfileModel extends UserProfile {
  const UserProfileModel({
    required super.uid,
    required super.fcmToken,
    required super.publicKeyJson,
    super.displayName,
    super.pairedWith,
    super.coupleId,
    required super.createdAt,
  });

  factory UserProfileModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) {
    final d = snap.data()!;
    return UserProfileModel(
      uid:           snap.id,
      fcmToken:      d['fcmToken'] as String? ?? '',
      publicKeyJson: d['publicKey'] as String? ?? '',
      displayName:   d['displayName'] as String?,
      pairedWith:    d['pairedWith'] as String?,
      coupleId:      d['coupleId'] as String?,
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'uid':        uid,
        'fcmToken':   fcmToken,
        'publicKey':  publicKeyJson,
        'displayName': displayName,
        'createdAt':  Timestamp.fromDate(createdAt),
      };
}
