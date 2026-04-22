// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_pairing_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/pair_session.dart';
import '../entities/user_profile.dart';

abstract interface class IPairingRepository {
  /// Creates or updates this device's profile in Firestore `users/{uid}`.
  /// Called once after auth + key generation are complete.
  Future<Either<PairingFailure, void>> initializeUserProfile(
    UserProfile profile,
  );

  /// Watches the current user's profile for pairing state changes.
  Stream<Either<PairingFailure, UserProfile>> watchUserProfile(String uid);

  /// Generates and writes a 6-digit pair code to `pairs/{code}` with a 5-min TTL.
  Future<Either<PairingFailure, String>> generatePairCode({
    required String initiatorUid,
    required String initiatorFcmToken,
    required String initiatorPublicKeyJson,
  });

  /// Accepts a pair code from the partner and creates the `couples` document.
  /// Also updates both `users/{uid}.pairedWith` fields.
  /// Enforces the 1-to-1 lock: throws [PairingFailure] if either user is
  /// already paired.
  Future<Either<PairingFailure, PairSession>> acceptPairCode({
    required String code,
    required String joinerUid,
    required String joinerFcmToken,
    required String joinerPublicKeyJson,
  });

  /// Returns the active [PairSession] for the current device, if paired.
  Future<Either<PairingFailure, PairSession?>> getActivePairSession(
    String uid,
  );

  /// Dissolves the pairing, clears both `users` documents and deletes the
  /// `couples` document.
  Future<Either<PairingFailure, void>> unpair(PairSession session);
}
