// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_message.dart
//  Domain entity for an ephemeral encrypted voice message.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:equatable/equatable.dart';

enum WhisperStatus {
  sending,      // recording + encrypting + uploading
  delivered,    // uploaded, FCM sent, pending partner play
  received,     // downloaded + decrypted, ready to play
  playing,      // currently playing on receiver's watch
  played,       // playback complete → WIPED locally
  wiped,        // remote file deleted by Cloud Function / client
  failed,
}

class WhisperMessage extends Equatable {
  const WhisperMessage({
    required this.id,
    required this.coupleId,
    required this.fromUid,
    required this.toUid,
    required this.storagePath,       // Firebase Storage path (remote)
    required this.durationSeconds,
    required this.createdAt,
    this.localPath,                  // temp file path (null after wipe)
    this.status = WhisperStatus.sending,
    this.fcmMessageId,
  });

  final String id;
  final String coupleId;
  final String fromUid;
  final String toUid;
  final String storagePath;
  final int durationSeconds;
  final DateTime createdAt;
  final String? localPath;
  final WhisperStatus status;
  final String? fcmMessageId;

  bool get isWiped    => status == WhisperStatus.wiped;
  bool get isDelivered => status == WhisperStatus.delivered;
  bool get isReceived  => status == WhisperStatus.received;

  WhisperMessage copyWith({
    String? localPath,
    WhisperStatus? status,
    String? fcmMessageId,
  }) =>
      WhisperMessage(
        id:              id,
        coupleId:        coupleId,
        fromUid:         fromUid,
        toUid:           toUid,
        storagePath:     storagePath,
        durationSeconds: durationSeconds,
        createdAt:       createdAt,
        localPath:       localPath   ?? this.localPath,
        status:          status      ?? this.status,
        fcmMessageId:    fcmMessageId ?? this.fcmMessageId,
      );

  @override
  List<Object?> get props => [id, status, localPath];
}
