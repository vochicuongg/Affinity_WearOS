// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pairing_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/pair_session.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/i_pairing_repository.dart';
import '../datasources/firestore_pairing_datasource.dart';
import '../models/user_profile_model.dart';

class PairingRepositoryImpl implements IPairingRepository {
  const PairingRepositoryImpl(this._ds);
  final FirestorePairingDataSource _ds;

  static const _tag = 'PairingRepository';

  @override
  Future<Either<PairingFailure, void>> initializeUserProfile(
    UserProfile profile,
  ) async {
    try {
      // Fetch the live FCM token at registration time.
      final fcmToken = await _ds.getFcmToken() ?? profile.fcmToken;
      final updated = UserProfileModel(
        uid:          profile.uid,
        fcmToken:     fcmToken,
        publicKeyJson: profile.publicKeyJson,
        displayName:  profile.displayName,
        pairedWith:   profile.pairedWith,
        coupleId:     profile.coupleId,
        createdAt:    profile.createdAt,
      );
      await _ds.saveUserProfile(updated);
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'initializeUserProfile failed', error: e, stack: st);
      return Left(PairingFailure(e.toString()));
    }
  }

  @override
  Stream<Either<PairingFailure, UserProfile>> watchUserProfile(String uid) =>
      _ds.watchUserProfile(uid).map(
            (profile) => profile != null
                ? Right(profile)
                : const Left(PairingFailure('Profile not found')),
          );

  @override
  Future<Either<PairingFailure, String>> generatePairCode({
    required String initiatorUid,
    required String initiatorFcmToken,
    required String initiatorPublicKeyJson,
  }) async {
    try {
      final code = await _ds.generatePairCode(
        initiatorUid:        initiatorUid,
        initiatorFcmToken:   initiatorFcmToken,
        initiatorPublicKeyJson: initiatorPublicKeyJson,
      );
      return Right(code);
    } catch (e, st) {
      Log.e(_tag, 'generatePairCode failed', error: e, stack: st);
      return Left(PairingFailure(e.toString()));
    }
  }

  @override
  Future<Either<PairingFailure, PairSession>> acceptPairCode({
    required String code,
    required String joinerUid,
    required String joinerFcmToken,
    required String joinerPublicKeyJson,
  }) async {
    try {
      final session = await _ds.acceptPairCode(
        code:                code,
        joinerUid:           joinerUid,
        joinerFcmToken:      joinerFcmToken,
        joinerPublicKeyJson: joinerPublicKeyJson,
      );
      return Right(session);
    } catch (e, st) {
      Log.e(_tag, 'acceptPairCode failed', error: e, stack: st);
      return Left(PairingFailure(e.toString()));
    }
  }

  @override
  Future<Either<PairingFailure, PairSession?>> getActivePairSession(
    String uid,
  ) async {
    try {
      final session = await _ds.getActivePairSession(uid);
      return Right(session);
    } catch (e, st) {
      Log.e(_tag, 'getActivePairSession failed', error: e, stack: st);
      return Left(PairingFailure(e.toString()));
    }
  }

  @override
  Future<Either<PairingFailure, void>> unpair(PairSession session) async {
    try {
      await _ds.unpair(session.coupleId, session.user1Uid, session.user2Uid);
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'unpair failed', error: e, stack: st);
      return Left(PairingFailure(e.toString()));
    }
  }
}
