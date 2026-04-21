// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — proximity_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/repositories/i_proximity_repository.dart';
import '../datasources/proximity_remote_datasource.dart';

class ProximityRepositoryImpl implements IProximityRepository {
  ProximityRepositoryImpl(this._remote, this._locationService);
  final ProximityRemoteDataSource _remote;
  final LocationService _locationService;

  static const _tag = 'ProximityRepository';

  @override
  Future<bool> requestPermission() =>
      _locationService.requestPermission();

  @override
  Future<Either<ProximityFailure, void>> uploadLocation({
    required String uid,
    required String coupleId,
    required FuzzedLocation location,
  }) async {
    try {
      await _remote.uploadLocation(
        uid: uid, coupleId: coupleId, location: location);
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'uploadLocation failed', error: e, stack: st);
      return Left(ProximityFailure(e.toString()));
    }
  }

  @override
  Future<Either<ProximityFailure, FuzzedLocation?>> getPartnerLocation({
    required String partnerUid,
    required String coupleId,
  }) async {
    try {
      final loc = await _remote.getPartnerLocation(
        partnerUid: partnerUid, coupleId: coupleId);
      return Right(loc);
    } catch (e, st) {
      Log.e(_tag, 'getPartnerLocation failed', error: e, stack: st);
      return Left(ProximityFailure(e.toString()));
    }
  }

  @override
  Stream<Either<ProximityFailure, FuzzedLocation>> watchPartnerLocation({
    required String partnerUid,
    required String coupleId,
  }) =>
      _remote
          .watchPartnerLocation(partnerUid: partnerUid, coupleId: coupleId)
          .map((loc) => loc != null
              ? Right<ProximityFailure, FuzzedLocation>(loc)
              : const Left(ProximityFailure('No location data')));
}
