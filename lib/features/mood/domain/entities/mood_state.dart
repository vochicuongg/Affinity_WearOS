// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — mood_state.dart
//  Domain entity representing one partner's emotional state.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

// ── Predefined Mood Colors ────────────────────────────────────────────────────

enum AffinityMood {
  passionate,
  calm,
  joyful,
  peaceful,
  melancholy,
  energetic,
  dreamy,
  neutral,
}

extension AffinityMoodX on AffinityMood {
  String get label => switch (this) {
        AffinityMood.passionate => 'Passionate',
        AffinityMood.calm       => 'Calm',
        AffinityMood.joyful     => 'Joyful',
        AffinityMood.peaceful   => 'Peaceful',
        AffinityMood.melancholy => 'Reflective',
        AffinityMood.energetic  => 'Energetic',
        AffinityMood.dreamy     => 'Dreamy',
        AffinityMood.neutral    => 'Neutral',
      };

  Color get color => switch (this) {
        AffinityMood.passionate => const Color(0xFFE8305A),  // deep rose
        AffinityMood.calm       => const Color(0xFF4A90D9),  // sky blue
        AffinityMood.joyful     => const Color(0xFFF5A623),  // golden
        AffinityMood.peaceful   => const Color(0xFF7ED321),  // sage green
        AffinityMood.melancholy => const Color(0xFF9B59B6),  // violet
        AffinityMood.energetic  => const Color(0xFFE74C3C),  // crimson
        AffinityMood.dreamy     => const Color(0xFFFF9CC8),  // soft pink
        AffinityMood.neutral    => const Color(0xFF888888),  // grey
      };

  String get emoji => switch (this) {
        AffinityMood.passionate => '🔥',
        AffinityMood.calm       => '🌊',
        AffinityMood.joyful     => '☀️',
        AffinityMood.peaceful   => '🌿',
        AffinityMood.melancholy => '🌙',
        AffinityMood.energetic  => '⚡',
        AffinityMood.dreamy     => '✨',
        AffinityMood.neutral    => '○',
      };

  String get id => name;

  static AffinityMood fromId(String id) =>
      AffinityMood.values.firstWhere(
        (m) => m.id == id,
        orElse: () => AffinityMood.neutral,
      );
}

// ── MoodState domain entity ───────────────────────────────────────────────────

class MoodState extends Equatable {
  const MoodState({
    required this.uid,
    required this.coupleId,
    required this.mood,
    required this.updatedAt,
    this.ciphertext = '',
  });

  final String uid;
  final String coupleId;
  final AffinityMood mood;
  final DateTime updatedAt;
  final String ciphertext; // AES-GCM encrypted payload stored in Firestore

  /// The actual tint colour for the tile UI.
  Color get color => mood.color;

  @override
  List<Object?> get props => [uid, mood, updatedAt];
}
