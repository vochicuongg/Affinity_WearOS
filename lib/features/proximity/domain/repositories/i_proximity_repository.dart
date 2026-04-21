// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_proximity_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/location/location_service.dart';

abstract interface class IProximityRepository {
  /// Requests location permission. Returns true if granted.
  Future<bool> requestPermission();

  /// Encrypts and writes [location] to Firestore for [uid] in [coupleId].
  Future<Either<ProximityFailure, void>> uploadLocation({
    required String uid,
    required String coupleId,
    required FuzzedLocation location,
  });

  /// Decrypts and returns the partner's last known fuzzed location.
  Future<Either<ProximityFailure, FuzzedLocation?>> getPartnerLocation({
    required String partnerUid,
    required String coupleId,
  });

  /// Streams the partner's fuzzed location in real-time.
  Stream<Either<ProximityFailure, FuzzedLocation>> watchPartnerLocation({
    required String partnerUid,
    required String coupleId,
  });
}
