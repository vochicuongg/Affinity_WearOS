// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_auth_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';

abstract interface class IAuthRepository {
  /// Watches Firebase Auth state changes in real time.
  Stream<AuthUser> get authStateChanges;

  /// Returns the currently signed-in user, or [AuthUser.empty].
  AuthUser get currentUser;

  /// Attempts a silent Google Sign-In using the watch's linked Google account.
  /// Falls back to anonymous auth if no Google account is available.
  Future<Either<AuthFailure, AuthUser>> signInSilently();

  /// Signs the user out and clears all local credentials.
  Future<Either<AuthFailure, void>> signOut();
}
