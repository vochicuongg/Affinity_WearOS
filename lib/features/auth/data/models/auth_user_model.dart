// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — auth_user_model.dart
//  Data-layer DTO: bridges Firebase User → AuthUser domain entity.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/entities/auth_user.dart';

class AuthUserModel extends AuthUser {
  const AuthUserModel({
    required super.uid,
    required super.email,
    super.displayName,
    super.photoUrl,
    super.isAnonymous,
  });

  factory AuthUserModel.fromFirebase(fb.User? user) {
    if (user == null) return const AuthUserModel(uid: '', email: '');
    return AuthUserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
      isAnonymous: user.isAnonymous,
    );
  }
}
