// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_local_datasource.dart
//  Wraps HapticService for the data layer.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/haptic/haptic_service.dart';
import '../../domain/entities/haptic_signal.dart';

class HapticLocalDataSource {
  HapticLocalDataSource(this._hapticService);
  final HapticService _hapticService;

  Future<Either<HapticFailure, void>> play(HapticSignal signal) =>
      _hapticService.playPattern(signal.pattern);

  Future<Either<HapticFailure, void>> playPattern(List<int> pattern) =>
      _hapticService.playPattern(pattern);

  Future<Either<HapticFailure, void>> playSignal(LoveSignal signal) =>
      _hapticService.playSignal(signal);

  Future<void> stop() => _hapticService.stop();
}
