// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_service.dart
//  Wraps the `vibration` package with Affinity-specific Love Signals and
//  the pattern playback logic needed by the haptic feature.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';
import 'package:vibration/vibration.dart';

import '../errors/failures.dart';
import '../utils/logger.dart';
import 'morse_encoder.dart';

// ── Pre-defined Love Signal patterns ─────────────────────────────────────────

enum LoveSignal {
  heartbeat,
  thinkingOfYou,
  iLoveYou,
  missYou,
  goodMorning,
  goodNight,
  sos,
  custom,
}

extension LoveSignalX on LoveSignal {
  String get displayName => switch (this) {
        LoveSignal.heartbeat     => '💓 Heartbeat',
        LoveSignal.thinkingOfYou => '💭 Thinking of you',
        LoveSignal.iLoveYou      => '❤️ I love you',
        LoveSignal.missYou       => '🥺 Miss you',
        LoveSignal.goodMorning   => '🌅 Good morning',
        LoveSignal.goodNight     => '🌙 Good night',
        LoveSignal.sos           => '🆘 SOS',
        LoveSignal.custom        => '✨ Custom',
      };

  // Each entry is a List<int> pattern: [wait,vibe,wait,vibe,...]
  // Silence at even indices, vibration at odd indices.
  List<int> get pattern => switch (this) {
        // Heartbeat: lub-DUB  lub-DUB  (classic cardiac rhythm)
        LoveSignal.heartbeat => [
            0, 80, 60, 160, 400,
            0, 80, 60, 160,
          ],

        // "TOY" in Morse: - --- -.--
        LoveSignal.thinkingOfYou =>
            MorseEncoder.textToPattern('TOY'),

        // "ILY" in Morse: .. .-.. -.--
        LoveSignal.iLoveYou =>
            MorseEncoder.textToPattern('ILY'),

        // "MY" in Morse: -- -.--
        LoveSignal.missYou =>
            MorseEncoder.textToPattern('MY'),

        // "GM" in Morse: --. --
        LoveSignal.goodMorning =>
            MorseEncoder.textToPattern('GM'),

        // "GN" in Morse: --. -.
        LoveSignal.goodNight =>
            MorseEncoder.textToPattern('GN'),

        // Classic SOS: ... --- ...
        LoveSignal.sos =>
            MorseEncoder.textToPattern('SOS'),

        LoveSignal.custom => [0, 200],
      };

  String get id => name; // used as Firestore/FCM signal identifier
}

// ── HapticService ─────────────────────────────────────────────────────────────

class HapticService {
  static const _tag = 'HapticService';

  bool? _hasVibrator;
  bool? _hasAmplitudeControl;

  // ── Device capability detection ───────────────────────────────────────────

  Future<bool> get isSupported async {
    _hasVibrator ??= await Vibration.hasVibrator();
    return _hasVibrator!;
  }

  Future<bool> get hasAmplitudeControl async {
    _hasAmplitudeControl ??= await Vibration.hasAmplitudeControl();
    return _hasAmplitudeControl!;
  }

  // ── Core playback ─────────────────────────────────────────────────────────

  /// Plays a [LoveSignal] predefined pattern.
  Future<Either<HapticFailure, void>> playSignal(LoveSignal signal) async {
    return _playPattern(signal.pattern, label: signal.displayName);
  }

  /// Plays a raw custom vibration [pattern].
  /// Pattern must be [wait, vibe, wait, vibe, ...] in milliseconds.
  Future<Either<HapticFailure, void>> playPattern(List<int> pattern) async {
    return _playPattern(pattern, label: 'custom');
  }

  /// Converts [text] to Morse and plays it.
  Future<Either<HapticFailure, void>> playMorseText(String text) async {
    final pattern = MorseEncoder.textToPattern(text);
    Log.i(_tag, 'Playing Morse for "$text": ${MorseEncoder.textToMorseString(text)}');
    return _playPattern(pattern, label: 'morse[$text]');
  }

  /// Plays a pattern from a raw list of tap durations (from the gesture detector).
  Future<Either<HapticFailure, void>> playTapSequence(
    List<int> tapDurationsMs,
  ) async {
    final pattern = MorseEncoder.tapsToPattern(tapDurationsMs);
    final letter  = MorseEncoder.tapsToLetter(tapDurationsMs);
    Log.i(_tag, 'Playing tap sequence → Morse letter: "$letter"');
    return _playPattern(pattern, label: 'tap→$letter');
  }

  /// Stops any currently running vibration immediately.
  Future<void> stop() async {
    await Vibration.cancel();
    Log.d(_tag, 'Vibration cancelled');
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  Future<Either<HapticFailure, void>> _playPattern(
    List<int> pattern, {
    required String label,
  }) async {
    try {
      final supported = await isSupported;
      if (!supported) {
        Log.w(_tag, 'Vibration not supported on this device');
        return const Left(HapticFailure('Vibration not supported on this device'));
      }

      if (pattern.isEmpty || pattern.length < 2) {
        return const Left(HapticFailure('Vibration pattern is too short'));
      }

      await Vibration.vibrate(pattern: pattern);
      Log.i(_tag, 'Vibration started [$label] pattern=${pattern.length} steps');
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'Vibration failed [$label]', error: e, stack: st);
      return Left(HapticFailure('Vibration failed: $e'));
    }
  }
}
