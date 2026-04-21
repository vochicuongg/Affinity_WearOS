// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — watch_haptics.dart
//  Lightweight haptic feedback utility for Wear OS button presses.
//
//  Uses Flutter's built-in HapticFeedback (routed to the vibrator).
//  Separate from the Affinity HapticService (which plays Morse patterns)
//  — this is purely for UI tactile confirmation.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/services.dart';

abstract final class WatchHaptics {
  /// Soft click — for toggle/nav button presses.
  static Future<void> tap() => HapticFeedback.selectionClick();

  /// Light bump — for quick-action buttons (Heartbeat, Love Signals).
  static Future<void> light() => HapticFeedback.lightImpact();

  /// Medium pulse — for PTT press start, mood selection.
  static Future<void> medium() => HapticFeedback.mediumImpact();

  /// Heavy thump — for destructive actions (delete, wipe confirm).
  static Future<void> heavy() => HapticFeedback.heavyImpact();

  /// Success double-tap — for sent confirmation.
  static Future<void> success() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  /// Error buzz — for failed operations.
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.heavyImpact();
  }
}
