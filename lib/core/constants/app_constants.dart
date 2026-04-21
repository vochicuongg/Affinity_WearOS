// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — app_constants.dart
//  Central repository for all compile-time constants.
// ═══════════════════════════════════════════════════════════════════════════
abstract final class AppConstants {
  // ── Firestore Collections ─────────────────────────────────────────────
  static const String colPairs    = 'pairs';
  static const String colUsers    = 'users';
  static const String colMessages = 'messages';
  static const String colHaptics  = 'haptics';
  static const String colMoods    = 'moods';
  static const String colNotes    = 'audio_notes';

  // ── Firestore Field Keys ──────────────────────────────────────────────
  static const String fieldFcmToken    = 'fcmToken';
  static const String fieldPublicKey   = 'publicKey';
  static const String fieldPairedWith  = 'pairedWith';
  static const String fieldPairCode    = 'pairCode';
  static const String fieldCreatedAt   = 'createdAt';
  static const String fieldExpiresAt   = 'expiresAt';
  static const String fieldNonce        = 'nonce';
  static const String fieldCiphertext  = 'ciphertext';
  static const String fieldPlayed      = 'played';

  // ── Secure Storage Keys ───────────────────────────────────────────────
  static const String keyRsaPrivate    = 'affinity_rsa_private_key';
  static const String keyRsaPublic     = 'affinity_rsa_public_key';
  static const String keyAesSession    = 'affinity_aes_session_key';
  static const String keyPairId        = 'affinity_pair_id';
  static const String keyPartnerId     = 'affinity_partner_id';

  // ── Anti-Replay ───────────────────────────────────────────────────────
  /// Maximum age of a message before it is considered a replay attack.
  static const Duration maxMessageAge = Duration(seconds: 30);

  /// Size of the nonce in bytes (128-bit).
  static const int nonceBytes = 16;

  // ── Haptic Morse Code ─────────────────────────────────────────────────
  /// Duration of a Morse dot vibration in milliseconds.
  static const int morseDotMs  = 100;

  /// Duration of a Morse dash vibration in milliseconds.
  static const int morseDashMs = 300;

  /// Gap between Morse symbols in milliseconds.
  static const int morseGapMs  = 100;

  /// Gap between Morse letters in milliseconds.
  static const int morseLetterGapMs = 300;

  // ── Audio ─────────────────────────────────────────────────────────────
  /// Maximum duration for a Love Note voice recording.
  static const Duration maxNoteRecordDuration = Duration(seconds: 30);

  /// Temporary audio file name prefix (before encryption).
  static const String tempAudioPrefix = 'affinity_temp_';

  // ── Proximity Vibe ────────────────────────────────────────────────────
  /// Distance (metres) at which proximity vibration begins.
  static const double proximityVibeStartMetres = 500.0;

  /// Distance (metres) at which vibration reaches maximum intensity.
  static const double proximityVibeMaxMetres   = 50.0;

  // ── Pairing ───────────────────────────────────────────────────────────
  /// Pair code length (numeric digits shown on screen for manual fallback).
  static const int pairCodeLength = 6;

  /// How long a pair invitation code remains valid.
  static const Duration pairCodeExpiry = Duration(minutes: 5);

  // ── App Metadata ──────────────────────────────────────────────────────
  static const String appName    = 'Affinity';
  static const String appVersion = '0.1.0';
}
