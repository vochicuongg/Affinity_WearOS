// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — mood_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mood_state.dart';
import '../../domain/repositories/i_mood_repository.dart';
import '../datasources/mood_remote_datasource.dart';

class MoodRepositoryImpl implements IMoodRepository {
  const MoodRepositoryImpl(this._remote);
  final MoodRemoteDataSource _remote;

  static const _tag = 'MoodRepository';

  @override
  Future<Either<MoodFailure, void>> updateMood({
    required String uid,
    required String coupleId,
    required AffinityMood mood,
  }) async {
    try {
      await _remote.updateMood(uid: uid, coupleId: coupleId, mood: mood);
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'updateMood failed', error: e, stack: st);
      return Left(MoodFailure(e.toString()));
    }
  }

  @override
  Stream<Either<MoodFailure, MoodState>> watchPartnerMood(
    String partnerUid,
    String coupleId,
  ) =>
      _remote.watchPartnerMood(partnerUid, coupleId).map(
            (state) => state != null
                ? Right<MoodFailure, MoodState>(state)
                : const Left(MoodFailure('No mood data')),
          );

  @override
  Future<Either<MoodFailure, AffinityMood>> getMyMood(
    String uid,
    String coupleId,
  ) async {
    try {
      final mood = await _remote.getMyMood(uid, coupleId);
      return Right(mood);
    } catch (e, st) {
      Log.e(_tag, 'getMyMood failed', error: e, stack: st);
      return Left(MoodFailure(e.toString()));
    }
  }
}
