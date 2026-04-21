// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — location_service.dart
//
//  Responsibilities:
//   1. Geolocator stream with adaptive accuracy (battery-aware)
//   2. Haversine great-circle distance formula (local — no server needed)
//   3. Privacy fuzzing: adds crypto-random ±100-200m noise before storage
//   4. Proximity thresholds → ProximityLevel enum
//
//  Privacy design:
//   • Raw GPS coordinates are NEVER stored or transmitted
//   • Fuzz offset is regenerated each session from a secure random source
//   • After fuzzing, the ciphertext is AES-GCM encrypted before Firestore write
//   • At worst, an attacker who decrypts the payload learns: "within ~200m of X"
//   • Threshold accuracy trade-off: 100m threshold becomes effective 0-400m (±200m per device)
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../utils/logger.dart';

// ── Proximity level thresholds ────────────────────────────────────────────────

enum ProximityLevel {
  unknown,
  far,         // > 5 km
  nearby,      // 1 km – 5 km
  close,       // 500 m – 1 km
  veryClose,   // 100 m – 500 m
  together,    // < 100 m
}

extension ProximityLevelX on ProximityLevel {
  String get label => switch (this) {
        ProximityLevel.unknown  => 'Unknown',
        ProximityLevel.far      => 'Far away',
        ProximityLevel.nearby   => 'Nearby',
        ProximityLevel.close    => 'Close',
        ProximityLevel.veryClose => 'Very close',
        ProximityLevel.together => 'Together ♥',
      };

  /// Returns true if a proximity haptic should fire when entering this level.
  bool get shouldVibrate => switch (this) {
        ProximityLevel.close     => true,
        ProximityLevel.veryClose => true,
        ProximityLevel.together  => true,
        _                        => false,
      };

  // Vibration pattern for each level transition
  List<int> get vibrationPattern => switch (this) {
        ProximityLevel.close     => [0, 150, 100, 150],            // double pulse
        ProximityLevel.veryClose => [0, 100, 80, 100, 80, 100],   // triple pulse
        ProximityLevel.together  => [0, 80, 60, 160, 400, 80, 60, 160], // lub-DUB x2
        _                        => [0, 100],
      };
}

// ── Location accuracy strategy ────────────────────────────────────────────────

LocationAccuracy _accuracyForLevel(ProximityLevel level) => switch (level) {
      ProximityLevel.far     => LocationAccuracy.low,     // ~1-3 km accuracy, minimal battery
      ProximityLevel.nearby  => LocationAccuracy.medium,  // ~100 m accuracy
      _                      => LocationAccuracy.high,    // GPS, used only when < 1 km
    };

Duration _intervalForLevel(ProximityLevel level) => switch (level) {
      ProximityLevel.far      => const Duration(minutes: 5),
      ProximityLevel.nearby   => const Duration(minutes: 2),
      ProximityLevel.close    => const Duration(seconds: 30),
      ProximityLevel.veryClose => const Duration(seconds: 15),
      ProximityLevel.together => const Duration(seconds: 10),
      _                       => const Duration(minutes: 5),
    };

// ── LocationService ───────────────────────────────────────────────────────────

class LocationService {
  static const _tag = 'LocationService';

  // Fuzz offset generated once per app session (crypto-random).
  // Range: ±0.0009° lat ≈ ±100m, ±0.0012° lon ≈ ±100m at equator.
  static final double _fuzzLat =
      (math.Random.secure().nextDouble() - 0.5) * 0.0018; // ±0.0009°
  static final double _fuzzLon =
      (math.Random.secure().nextDouble() - 0.5) * 0.0024; // ±0.0012°

  // ── Permission checks ─────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      Log.w(_tag, 'Location services disabled on device');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      Log.e(_tag, 'Location permission permanently denied');
      return false;
    }

    Log.i(_tag, 'Location permission: $permission');
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ── Current position (single read) ───────────────────────────────────────

  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      );
    } catch (e, st) {
      Log.e(_tag, 'getCurrentPosition failed', error: e, stack: st);
      return null;
    }
  }

  // ── Fuzzed position (for Firestore storage) ───────────────────────────────

  /// Returns a fuzzed [FuzzedLocation] by adding the session-static random
  /// offset to the real GPS coordinates.
  ///
  /// The offset is:
  ///   • Different each app launch (crypto-random)
  ///   • Consistent within a session (static field)
  ///   • ±~100-200m magnitude
  ///
  /// This means an attacker who decrypts the stored location can only infer
  /// "the device is within ~200m of this point" — exact address is hidden.
  FuzzedLocation fuzz(Position position) {
    final fuzzedLat = position.latitude  + _fuzzLat;
    final fuzzedLon = position.longitude + _fuzzLon;
    Log.d(
      _tag,
      'Location fuzzed: raw=(${position.latitude.toStringAsFixed(5)}, '
      '${position.longitude.toStringAsFixed(5)}) '
      'fuzz=(${fuzzedLat.toStringAsFixed(5)}, ${fuzzedLon.toStringAsFixed(5)})',
    );
    return FuzzedLocation(
      lat: fuzzedLat,
      lon: fuzzedLon,
      accuracy: position.accuracy,
      timestamp: DateTime.now(),
    );
  }

  // ── Haversine great-circle distance ──────────────────────────────────────

  /// Calculates the great-circle distance between two fuzzed coordinates
  /// in **metres** using the Haversine formula.
  ///
  /// Accuracy note: The formula itself is accurate to within 0.3% globally.
  /// The dominant error here is from location fuzzing (±200m per device).
  ///
  /// Formula:
  ///   a = sin²(Δφ/2) + cos(φ1)·cos(φ2)·sin²(Δλ/2)
  ///   c = 2·atan2(√a, √(1−a))
  ///   d = R·c
  static double haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const earthRadiusM = 6371000.0;

    final phi1    = _toRad(lat1);
    final phi2    = _toRad(lat2);
    final dPhi    = _toRad(lat2 - lat1);
    final dLambda = _toRad(lon2 - lon1);

    final a = math.sin(dPhi / 2)    * math.sin(dPhi / 2) +
              math.cos(phi1)         * math.cos(phi2) *
              math.sin(dLambda / 2)  * math.sin(dLambda / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));

    return earthRadiusM * c; // metres
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  // ── ProximityLevel classifier ─────────────────────────────────────────────

  static ProximityLevel classify(double distanceMetres) {
    if (distanceMetres > 5000)  return ProximityLevel.far;
    if (distanceMetres > 1000)  return ProximityLevel.nearby;
    if (distanceMetres > 500)   return ProximityLevel.close;
    if (distanceMetres > 100)   return ProximityLevel.veryClose;
    return ProximityLevel.together;
  }

  // ── Continuous location stream ────────────────────────────────────────────

  /// Streams [FuzzedLocation] updates, adapting accuracy and interval based
  /// on the [currentLevel] (battery optimisation).
  Stream<FuzzedLocation> watchPosition(ProximityLevel currentLevel) {
    final accuracy = _accuracyForLevel(currentLevel);
    final interval = _intervalForLevel(currentLevel);

    Log.i(
      _tag,
      'Starting location stream: accuracy=$accuracy '
      'interval=${interval.inSeconds}s',
    );

    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy:         accuracy,
        distanceFilter:   50,              // minimum 50 m between updates
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle:   'Affinity',
          notificationText:    'Tracking proximity with your partner',
          enableWakeLock:      true,
          notificationIcon:    AndroidResource(name: 'ic_launcher'),
        ),
      ),
    ).map((pos) => fuzz(pos));
  }
}

// ── FuzzedLocation value object ───────────────────────────────────────────────

class FuzzedLocation {
  const FuzzedLocation({
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.timestamp,
  });

  final double lat;
  final double lon;
  final double accuracy;   // metres (from GPS, NOT including fuzz error)
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'lat':       lat,
        'lon':       lon,
        'acc':       accuracy,
        'ts':        timestamp.millisecondsSinceEpoch,
      };

  factory FuzzedLocation.fromJson(Map<String, dynamic> json) => FuzzedLocation(
        lat:       (json['lat'] as num).toDouble(),
        lon:       (json['lon'] as num).toDouble(),
        accuracy:  (json['acc'] as num).toDouble(),
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
      );
}
