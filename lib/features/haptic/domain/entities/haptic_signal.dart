// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_signal.dart
//  Domain entity representing one haptic signal event.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

import '../../../../core/haptic/haptic_service.dart';

class HapticSignal extends Equatable {
  const HapticSignal({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.signal,
    required this.pattern,
    required this.ciphertext,   // encrypted payload stored in Firestore
    required this.nonce,
    required this.timestamp,
    this.played = false,
  });

  final String id;
  final String fromUid;
  final String toUid;
  final LoveSignal signal;
  final List<int> pattern;     // raw vibration pattern [wait,vibe,...]
  final String ciphertext;     // base64 AES-GCM ciphertext
  final String nonce;
  final DateTime timestamp;
  final bool played;

  @override
  List<Object?> get props => [id, fromUid, toUid, signal, nonce, timestamp];
}
