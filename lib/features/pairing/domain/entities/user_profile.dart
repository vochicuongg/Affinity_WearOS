// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — user_profile.dart
//  Firestore representation of a device registered in the `users` collection.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    required this.fcmToken,
    required this.publicKeyJson,
    this.displayName,
    this.pairedWith,
    this.coupleId,
    required this.createdAt,
  });

  final String uid;
  final String fcmToken;
  final String publicKeyJson;   // RSA public key JSON {"n":...,"e":...}
  final String? displayName;
  final String? pairedWith;     // uid of paired partner (null if unpaired)
  final String? coupleId;       // ID of the couples document (null if unpaired)
  final DateTime createdAt;

  bool get isPaired => pairedWith != null && pairedWith!.isNotEmpty;

  UserProfile copyWith({
    String? fcmToken,
    String? publicKeyJson,
    String? displayName,
    String? pairedWith,
    String? coupleId,
  }) =>
      UserProfile(
        uid: uid,
        fcmToken: fcmToken ?? this.fcmToken,
        publicKeyJson: publicKeyJson ?? this.publicKeyJson,
        displayName: displayName ?? this.displayName,
        pairedWith: pairedWith ?? this.pairedWith,
        coupleId: coupleId ?? this.coupleId,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props =>
      [uid, fcmToken, publicKeyJson, displayName, pairedWith, coupleId];
}
