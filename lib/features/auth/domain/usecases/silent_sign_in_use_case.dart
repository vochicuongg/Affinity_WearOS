// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — silent_sign_in_use_case.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/auth_user.dart';
import '../repositories/i_auth_repository.dart';

class SilentSignInUseCase {
  const SilentSignInUseCase(this._repository);
  final IAuthRepository _repository;

  Future<Either<AuthFailure, AuthUser>> call() => _repository.signInSilently();
}
