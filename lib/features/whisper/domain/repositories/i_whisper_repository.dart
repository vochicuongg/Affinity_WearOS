// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — i_whisper_repository.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/whisper_message.dart';

abstract interface class IWhisperRepository {
  /// Records, encrypts, uploads, and signals a whisper message.
  /// The local temp file is securely wiped after successful upload.
  Future<Either<RecordingFailure, WhisperMessage>> sendWhisper({
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String coupleId,
    required String recordedFilePath,
    required int durationSeconds,
  });

  /// Downloads and decrypts an incoming whisper to a temp file.
  Future<Either<PlaybackFailure, String>> downloadAndDecrypt({
    required WhisperMessage message,
  });

  /// Plays the decrypted temp file at whisper volume.
  /// Triggers secure wipe + Firestore deletion flag after playback.
  Future<Either<PlaybackFailure, void>> playAndWipe({
    required WhisperMessage message,
    required String decryptedLocalPath,
  });

  /// Streams incoming whisper signals for the current user.
  Stream<Either<RecordingFailure, WhisperMessage>> watchIncomingWhispers({
    required String myUid,
    required String coupleId,
  });

  /// Marks remote Firestore document for deletion (Cloud Function trigger).
  Future<void> requestRemoteWipe(WhisperMessage message);
}
