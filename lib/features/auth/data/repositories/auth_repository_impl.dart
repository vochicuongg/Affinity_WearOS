// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — auth_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/firebase_auth_datasource.dart';

class AuthRepositoryImpl implements IAuthRepository {
  const AuthRepositoryImpl(this._dataSource);
  final IAuthRemoteDataSource _dataSource;

  static const _tag = 'AuthRepository';

  @override
  Stream<AuthUser> get authStateChanges => _dataSource.authStateChanges;

  @override
  AuthUser get currentUser => _dataSource.currentUser;

  @override
  Future<Either<AuthFailure, AuthUser>> signInSilently() async {
    try {
      final user = await _dataSource.signInSilently();
      return Right(user);
    } catch (e, st) {
      Log.e(_tag, 'signInSilently failed', error: e, stack: st);
      return Left(AuthFailure(e.toString()));
    }
  }

  @override
  Future<Either<AuthFailure, void>> signOut() async {
    try {
      await _dataSource.signOut();
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'signOut failed', error: e, stack: st);
      return Left(AuthFailure(e.toString()));
    }
  }
}
