// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — proximity_state.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

import '../../../../core/location/location_service.dart';

class ProximityState extends Equatable {
  const ProximityState({
    this.level = ProximityLevel.unknown,
    this.distanceMetres,
    this.isTracking = false,
    this.errorMessage,
    this.myLastUpdated,
    this.partnerLastUpdated,
  });

  final ProximityLevel level;
  final double? distanceMetres;
  final bool isTracking;
  final String? errorMessage;
  final DateTime? myLastUpdated;
  final DateTime? partnerLastUpdated;

  String get distanceLabel {
    final d = distanceMetres;
    if (d == null) return '--';
    if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)} km';
    return '${d.round()} m';
  }

  ProximityState copyWith({
    ProximityLevel? level,
    double? distanceMetres,
    bool? isTracking,
    String? errorMessage,
    DateTime? myLastUpdated,
    DateTime? partnerLastUpdated,
  }) =>
      ProximityState(
        level:               level               ?? this.level,
        distanceMetres:      distanceMetres      ?? this.distanceMetres,
        isTracking:          isTracking          ?? this.isTracking,
        errorMessage:        errorMessage        ?? this.errorMessage,
        myLastUpdated:       myLastUpdated       ?? this.myLastUpdated,
        partnerLastUpdated:  partnerLastUpdated  ?? this.partnerLastUpdated,
      );

  @override
  List<Object?> get props => [level, distanceMetres, isTracking, errorMessage];
}
