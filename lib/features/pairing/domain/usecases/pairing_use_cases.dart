// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pairing_use_cases.dart
//  All three pairing use cases in one file (they are thin delegation wrappers).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/pair_session.dart';
import '../entities/user_profile.dart';
import '../repositories/i_pairing_repository.dart';

// ── 1. Initialize User Profile ────────────────────────────────────────────

class InitializeUserProfileUseCase {
  const InitializeUserProfileUseCase(this._repo);
  final IPairingRepository _repo;

  Future<Either<PairingFailure, void>> call(UserProfile profile) =>
      _repo.initializeUserProfile(profile);
}

// ── 2. Generate Pair Code ─────────────────────────────────────────────────

class GeneratePairCodeParams {
  const GeneratePairCodeParams({
    required this.initiatorUid,
    required this.initiatorFcmToken,
    required this.initiatorPublicKeyJson,
  });
  final String initiatorUid;
  final String initiatorFcmToken;
  final String initiatorPublicKeyJson;
}

class GeneratePairCodeUseCase {
  const GeneratePairCodeUseCase(this._repo);
  final IPairingRepository _repo;

  Future<Either<PairingFailure, String>> call(
    GeneratePairCodeParams params,
  ) =>
      _repo.generatePairCode(
        initiatorUid: params.initiatorUid,
        initiatorFcmToken: params.initiatorFcmToken,
        initiatorPublicKeyJson: params.initiatorPublicKeyJson,
      );
}

// ── 3. Accept Pair Code ───────────────────────────────────────────────────

class AcceptPairCodeParams {
  const AcceptPairCodeParams({
    required this.code,
    required this.joinerUid,
    required this.joinerFcmToken,
    required this.joinerPublicKeyJson,
  });
  final String code;
  final String joinerUid;
  final String joinerFcmToken;
  final String joinerPublicKeyJson;
}

class AcceptPairCodeUseCase {
  const AcceptPairCodeUseCase(this._repo);
  final IPairingRepository _repo;

  Future<Either<PairingFailure, PairSession>> call(
    AcceptPairCodeParams params,
  ) =>
      _repo.acceptPairCode(
        code: params.code,
        joinerUid: params.joinerUid,
        joinerFcmToken: params.joinerFcmToken,
        joinerPublicKeyJson: params.joinerPublicKeyJson,
      );
}
