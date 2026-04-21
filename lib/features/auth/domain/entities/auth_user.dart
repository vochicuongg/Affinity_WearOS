// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — auth_user.dart
//  Domain entity representing an authenticated device identity.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.isAnonymous = false,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final bool isAnonymous;

  /// Sentinel value for the unauthenticated / loading state.
  static const empty = AuthUser(uid: '', email: '');

  bool get isEmpty => uid.isEmpty;
  bool get isNotEmpty => uid.isNotEmpty;

  @override
  List<Object?> get props => [uid, email, displayName, photoUrl, isAnonymous];
}
