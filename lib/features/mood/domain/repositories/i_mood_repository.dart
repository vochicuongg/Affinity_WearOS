// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_mood_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/mood_state.dart';

abstract interface class IMoodRepository {
  /// Encrypts and persists [mood] to Firestore for [uid] in [coupleId].
  Future<Either<MoodFailure, void>> updateMood({
    required String uid,
    required String coupleId,
    required AffinityMood mood,
  });

  /// Streams the partner's latest mood (real-time, decrypted).
  Stream<Either<MoodFailure, MoodState>> watchPartnerMood(
    String partnerUid,
    String coupleId,
  );

  /// Returns my own last-set mood (or [AffinityMood.neutral] if unset).
  Future<Either<MoodFailure, AffinityMood>> getMyMood(
    String uid,
    String coupleId,
  );
}
