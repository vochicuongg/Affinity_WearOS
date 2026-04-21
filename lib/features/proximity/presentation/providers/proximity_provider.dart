// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — proximity_provider.dart
//  ProximityNotifier: location stream + Haversine + threshold-triggered haptics.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../../../core/location/location_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pairing/presentation/providers/pairing_provider.dart';
import '../../data/datasources/proximity_remote_datasource.dart';
import '../../data/repositories/proximity_repository_impl.dart';
import '../../domain/entities/proximity_state.dart';
import '../../domain/repositories/i_proximity_repository.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final locationServiceProvider = Provider<LocationService>(
  (_) => LocationService(),
);

final proximityRemoteDSProvider = Provider<ProximityRemoteDataSource>((ref) =>
    ProximityRemoteDataSource(
        encryption: ref.read(encryptionServiceProvider)));

final proximityRepositoryProvider = Provider<IProximityRepository>((ref) {
  return ProximityRepositoryImpl(
    ref.read(proximityRemoteDSProvider),
    ref.read(locationServiceProvider),
  );
});

// ── ProximityNotifier ─────────────────────────────────────────────────────

class ProximityNotifier extends Notifier<ProximityState> {
  static const _tag = 'ProximityNotifier';

  StreamSubscription<FuzzedLocation>? _myLocationSub;
  StreamSubscription<FuzzedLocation?>? _partnerLocationSub;
  FuzzedLocation? _myLocation;
  FuzzedLocation? _partnerLocation;
  ProximityLevel  _lastLevel = ProximityLevel.unknown;

  @override
  ProximityState build() => const ProximityState();

  IProximityRepository get _repo => ref.read(proximityRepositoryProvider);

  // ── Start tracking ────────────────────────────────────────────────────────

  Future<void> startTracking() async {
    final pairingState = ref.read(pairingNotifierProvider);
    final session      = pairingState.session;
    final authState    = ref.read(authNotifierProvider);

    if (session == null || !authState.isAuthenticated) {
      state = state.copyWith(errorMessage: 'Not paired — cannot track proximity');
      return;
    }

    // Request location permission
    final granted = await _repo.requestPermission();
    if (!granted) {
      state = state.copyWith(errorMessage: 'Location permission denied');
      return;
    }

    state = state.copyWith(isTracking: true, errorMessage: null);
    Log.i(_tag, 'Proximity tracking started');

    final myUid      = authState.user.uid;
    final partnerUid = myUid == session.user1Uid ? session.user2Uid : session.user1Uid;
    final coupleId   = session.coupleId;
    final locationSvc = ref.read(locationServiceProvider);

    // ── Stream own location → fuzz → upload → calculate distance ──────────
    await _myLocationSub?.cancel();
    _myLocationSub = locationSvc
        .watchPosition(state.level)
        .listen((fuzzed) async {
      _myLocation = fuzzed;

      // Upload fuzzed + encrypted location to Firestore
      await _repo.uploadLocation(
        uid:      myUid,
        coupleId: coupleId,
        location: fuzzed,
      );

      state = state.copyWith(myLastUpdated: fuzzed.timestamp);
      _recalculate(locationSvc);
    });

    // ── Stream partner location → calculate distance ───────────────────────
    await _partnerLocationSub?.cancel();
    _partnerLocationSub = _repo
        .watchPartnerLocation(partnerUid: partnerUid, coupleId: coupleId)
        .map((e) => e.fold((_) => null, (l) => l))
        .where((l) => l != null)
        .cast<FuzzedLocation>()
        .listen((loc) {
      _partnerLocation = loc;
      state = state.copyWith(partnerLastUpdated: loc.timestamp);
      _recalculate(locationSvc);
    });
  }

  void stopTracking() {
    _myLocationSub?.cancel();
    _partnerLocationSub?.cancel();
    _myLocationSub = null;
    _partnerLocationSub = null;
    state = const ProximityState();
    Log.i(_tag, 'Proximity tracking stopped');
  }

  // ── Core distance calculation ─────────────────────────────────────────────

  void _recalculate(LocationService locationSvc) {
    final my      = _myLocation;
    final partner = _partnerLocation;
    if (my == null || partner == null) return;

    final distM = LocationService.haversineDistance(
      my.lat, my.lon,
      partner.lat, partner.lon,
    );

    final newLevel = LocationService.classify(distM);

    Log.i(
      _tag,
      '📍 Distance: ${distM.round()}m | Level: ${newLevel.label} '
      '(fuzz error: ±~200m)',
    );

    // ── Proximity haptic trigger on level change ───────────────────────────
    if (newLevel != _lastLevel && newLevel.shouldVibrate) {
      _triggerProximityHaptic(newLevel);
    }
    _lastLevel = newLevel;

    state = state.copyWith(
      level:          newLevel,
      distanceMetres: distM,
    );
  }

  // ── Proximity haptic ──────────────────────────────────────────────────────

  Future<void> _triggerProximityHaptic(ProximityLevel level) async {
    Log.i(_tag, '💫 Proximity haptic: ${level.label}');
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        await Vibration.vibrate(pattern: level.vibrationPattern);
      }
    } catch (e) {
      Log.w(_tag, 'Proximity haptic failed: $e');
    }
  }
}

final proximityNotifierProvider =
    NotifierProvider<ProximityNotifier, ProximityState>(
  ProximityNotifier.new,
);
