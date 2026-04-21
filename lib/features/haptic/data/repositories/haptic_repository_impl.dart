// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/haptic/haptic_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/haptic_signal.dart';
import '../../domain/repositories/i_haptic_repository.dart';
import '../datasources/haptic_local_datasource.dart';
import '../datasources/haptic_remote_datasource.dart';

class HapticRepositoryImpl implements IHapticRepository {
  const HapticRepositoryImpl(this._remote, this._local);

  static const _tag = 'HapticRepository';
  final HapticRemoteDataSource _remote;
  final HapticLocalDataSource _local;

  @override
  Future<Either<HapticFailure, void>> sendSignal({
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String coupleId,
    required LoveSignal signal,
    List<int>? customPattern,
  }) async {
    try {
      await _remote.sendSignal(
        fromUid:       fromUid,
        toUid:         toUid,
        toFcmToken:    toFcmToken,
        coupleId:      coupleId,
        signal:        signal,
        customPattern: customPattern,
      );
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'sendSignal failed', error: e, stack: st);
      return Left(HapticFailure(e.toString()));
    }
  }

  @override
  Stream<Either<HapticFailure, HapticSignal>> watchIncomingSignals(
    String uid,
    String coupleId,
  ) =>
      _remote.watchIncomingSignals(uid, coupleId).map(
            (signal) => signal != null
                ? Right<HapticFailure, HapticSignal>(signal)
                : const Left(HapticFailure('No signal')),
          );

  @override
  Future<Either<HapticFailure, void>> playSignal(HapticSignal signal) =>
      _local.play(signal);

  @override
  Future<Either<HapticFailure, void>> playPattern(List<int> pattern) =>
      _local.playPattern(pattern);

  @override
  Future<Either<HapticFailure, void>> playLocalSignal(LoveSignal signal) =>
      _local.playSignal(signal);

  @override
  Future<Either<HapticFailure, void>> markPlayed(
    String signalId,
    String coupleId,
  ) async {
    try {
      await _remote.markPlayed(signalId, coupleId);
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'markPlayed failed', error: e, stack: st);
      return Left(HapticFailure(e.toString()));
    }
  }
}
