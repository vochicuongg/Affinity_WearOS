// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_use_cases.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/haptic/haptic_service.dart';
import '../entities/haptic_signal.dart';
import '../repositories/i_haptic_repository.dart';

// ── Send Haptic Signal ────────────────────────────────────────────────────

class SendHapticSignalParams {
  const SendHapticSignalParams({
    required this.fromUid,
    required this.toUid,
    required this.toFcmToken,
    required this.coupleId,
    required this.signal,
    this.customPattern,
  });
  final String fromUid;
  final String toUid;
  final String toFcmToken;
  final String coupleId;
  final LoveSignal signal;
  final List<int>? customPattern;
}

class SendHapticSignalUseCase {
  const SendHapticSignalUseCase(this._repo);
  final IHapticRepository _repo;

  Future<Either<HapticFailure, void>> call(SendHapticSignalParams p) =>
      _repo.sendSignal(
        fromUid:       p.fromUid,
        toUid:         p.toUid,
        toFcmToken:    p.toFcmToken,
        coupleId:      p.coupleId,
        signal:        p.signal,
        customPattern: p.customPattern,
      );
}

// ── Watch Incoming Signals ────────────────────────────────────────────────

class WatchIncomingSignalsUseCase {
  const WatchIncomingSignalsUseCase(this._repo);
  final IHapticRepository _repo;

  Stream<Either<HapticFailure, HapticSignal>> call(
    String uid,
    String coupleId,
  ) =>
      _repo.watchIncomingSignals(uid, coupleId);
}

// ── Play Signal ───────────────────────────────────────────────────────────

class PlaySignalUseCase {
  const PlaySignalUseCase(this._repo);
  final IHapticRepository _repo;

  Future<Either<HapticFailure, void>> call(HapticSignal signal) =>
      _repo.playSignal(signal);
}
