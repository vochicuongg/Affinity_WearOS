// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_haptic_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/haptic/haptic_service.dart';
import '../entities/haptic_signal.dart';

abstract interface class IHapticRepository {
  /// Encrypts and writes a haptic signal to Firestore.
  /// The Cloud Function then pushes FCM to the partner.
  Future<Either<HapticFailure, void>> sendSignal({
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String coupleId,
    required LoveSignal signal,
    List<int>? customPattern,
  });

  /// Streams incoming haptic signals addressed to [uid] (foreground delivery).
  Stream<Either<HapticFailure, HapticSignal>> watchIncomingSignals(
    String uid,
    String coupleId,
  );

  /// Plays the vibration pattern for [signal] on the local device.
  Future<Either<HapticFailure, void>> playSignal(HapticSignal signal);

  /// Plays a custom raw vibration [pattern] immediately.
  Future<Either<HapticFailure, void>> playPattern(List<int> pattern);

  /// Plays a [LoveSignal] predefined pattern immediately (no Firestore write).
  Future<Either<HapticFailure, void>> playLocalSignal(LoveSignal signal);

  /// Marks a signal as played in Firestore so it won't re-trigger.
  Future<Either<HapticFailure, void>> markPlayed(
    String signalId,
    String coupleId,
  );
}
