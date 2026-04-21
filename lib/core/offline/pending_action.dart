// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pending_action.dart
//  Hive model for offline queue entries.
//
//  Every send operation (Haptic, Mood, Whisper) that fails due to network
//  issues is persisted here and retried once connectivity is restored.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:hive_flutter/hive_flutter.dart';

part 'pending_action.g.dart';

// ── Action type constants ─────────────────────────────────────────────────────

class PendingActionType {
  static const haptic    = 'haptic';
  static const mood      = 'mood';
  static const whisper   = 'whisper';
  static const proximity = 'proximity';
}

// ── PendingAction Hive model ──────────────────────────────────────────────────

@HiveType(typeId: 10)
class PendingAction extends HiveObject {
  PendingAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
    this.nextRetryAt,
  });

  @HiveField(0) final String id;
  @HiveField(1) final String type;                   // PendingActionType
  @HiveField(2) final Map<String, dynamic> payload;  // serialised action data
  @HiveField(3) final DateTime createdAt;
  @HiveField(4) int retryCount;
  @HiveField(5) DateTime? nextRetryAt;

  static const int _maxRetries = 5;
  static const _backoffBase = Duration(minutes: 2);

  bool get isExpired => retryCount >= _maxRetries;

  bool get isDue {
    final next = nextRetryAt;
    if (next == null) return true;
    return DateTime.now().isAfter(next);
  }

  void markRetried() {
    retryCount++;
    // Exponential backoff: 2, 4, 8, 16, 32 minutes
    final backoff = _backoffBase * (1 << (retryCount - 1).clamp(0, 4));
    nextRetryAt   = DateTime.now().add(backoff);
  }
}
