// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — failures.dart
//  Domain-layer failure types using a sealed class hierarchy.
//  Used with dartz Either<Failure, T> for functional error propagation.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

/// Base class for all domain-layer failures.
sealed class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Network & Firebase ────────────────────────────────────────────────────

/// Thrown when a Firebase / Firestore operation fails.
final class FirebaseFailure extends Failure {
  const FirebaseFailure(super.message);
}

/// Thrown when no active network connection is available.
final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No network connection available.']);
}

/// Thrown when an FCM push notification cannot be delivered.
final class MessagingFailure extends Failure {
  const MessagingFailure(super.message);
}

// ── Authentication & Pairing ──────────────────────────────────────────────

/// Thrown when Firebase Auth fails (sign-in, token refresh, etc.).
final class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Thrown when a pairing operation fails (invalid code, expired, etc.).
final class PairingFailure extends Failure {
  const PairingFailure(super.message);
}

/// Thrown when an operation requires a paired partner but none is found.
final class NotPairedFailure extends Failure {
  const NotPairedFailure([super.message = 'No partner device is paired.']);
}

// ── Security & Encryption ─────────────────────────────────────────────────

/// Thrown when RSA/AES encryption or decryption fails.
final class EncryptionFailure extends Failure {
  const EncryptionFailure(super.message);
}

/// Thrown when a received message fails the anti-replay check.
final class ReplayAttackFailure extends Failure {
  const ReplayAttackFailure([
    super.message = 'Message rejected: potential replay attack detected.',
  ]);
}

/// Thrown when a cryptographic signature cannot be verified.
final class SignatureFailure extends Failure {
  const SignatureFailure(super.message);
}

// ── Audio ─────────────────────────────────────────────────────────────────

/// Thrown when audio recording fails.
final class RecordingFailure extends Failure {
  const RecordingFailure(super.message);
}

/// Thrown when audio playback fails.
final class PlaybackFailure extends Failure {
  const PlaybackFailure(super.message);
}

/// Thrown when secure audio wipe fails.
final class SecureWipeFailure extends Failure {
  const SecureWipeFailure(super.message);
}

// ── Haptic ────────────────────────────────────────────────────────────────

/// Thrown when a vibration pattern cannot be executed on this device.
final class HapticFailure extends Failure {
  const HapticFailure(super.message);
}

// ── Mood ─────────────────────────────────────────────────────────────────

/// Thrown when a mood update or stream read fails.
final class MoodFailure extends Failure {
  const MoodFailure(super.message);
}

// ── Proximity ──────────────────────────────────────────────────────────

/// Thrown when a location permission, upload, or read operation fails.
final class ProximityFailure extends Failure {
  const ProximityFailure(super.message);
}

// ── Cache / Storage ───────────────────────────────────────────────────────

/// Thrown when reading from / writing to secure local storage fails.
final class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

// ── Unexpected ────────────────────────────────────────────────────────────

/// Catch-all for unhandled exceptions surfaced to the domain layer.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure([
    super.message = 'An unexpected error occurred. Please try again.',
  ]);
}
