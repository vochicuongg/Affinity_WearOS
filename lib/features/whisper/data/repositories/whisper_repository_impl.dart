// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/whisper_message.dart';
import '../../domain/repositories/i_whisper_repository.dart';
import '../datasources/whisper_local_datasource.dart';
import '../datasources/whisper_remote_datasource.dart';

class WhisperRepositoryImpl implements IWhisperRepository {
  WhisperRepositoryImpl(this._local, this._remote);
  final WhisperLocalDataSource  _local;
  final WhisperRemoteDataSource _remote;

  static const _tag  = 'WhisperRepository';
  static const _uuid = Uuid();

  // ── Send ──────────────────────────────────────────────────────────────────

  @override
  Future<Either<RecordingFailure, WhisperMessage>> sendWhisper({
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String coupleId,
    required String recordedFilePath,
    required int durationSeconds,
  }) async {
    try {
      final messageId = _uuid.v4();

      // ① Encrypt the raw m4a file (wipes original after encryption)
      final encPath  = await _local.encryptAudioFile(recordedFilePath);
      final encBytes = await File(encPath).readAsBytes();

      // ② Upload to Firebase Storage
      final storagePath = await _remote.uploadEncryptedAudio(
        coupleId: coupleId,
        messageId: messageId,
        encryptedBytes: Uint8List.fromList(encBytes),
      );

      // ③ Secure-wipe the local .enc file (no longer needed)
      await _local.wipeAllTempFiles();

      // ④ Write Firestore signal → triggers FCM via Cloud Function
      await _remote.writeWhisperSignal(
        messageId:       messageId,
        coupleId:        coupleId,
        fromUid:         fromUid,
        toUid:           toUid,
        toFcmToken:      toFcmToken,
        storagePath:     storagePath,
        durationSeconds: durationSeconds,
      );

      Log.i(_tag, '✅ Whisper sent: $messageId (${durationSeconds}s)');

      return Right(WhisperMessage(
        id:              messageId,
        coupleId:        coupleId,
        fromUid:         fromUid,
        toUid:           toUid,
        storagePath:     storagePath,
        durationSeconds: durationSeconds,
        createdAt:       DateTime.now(),
        status:          WhisperStatus.delivered,
      ));
    } catch (e, st) {
      Log.e(_tag, 'sendWhisper failed', error: e, stack: st);
      return Left(RecordingFailure(e.toString()));
    }
  }

  // ── Receive: download + decrypt ───────────────────────────────────────────

  @override
  Future<Either<PlaybackFailure, String>> downloadAndDecrypt({
    required WhisperMessage message,
  }) async {
    try {
      final encBytes = await _remote.downloadEncryptedAudio(
        coupleId:  message.coupleId,
        messageId: message.id,
      );

      final decPath = await _local.decryptAudioBytes(encBytes, message.id);
      Log.i(_tag, 'Decrypted to: $decPath');
      return Right(decPath);
    } catch (e, st) {
      Log.e(_tag, 'downloadAndDecrypt failed', error: e, stack: st);
      return Left(PlaybackFailure(e.toString()));
    }
  }

  // ── Play + wipe ───────────────────────────────────────────────────────────

  @override
  Future<Either<PlaybackFailure, void>> playAndWipe({
    required WhisperMessage message,
    required String decryptedLocalPath,
  }) async {
    try {
      await _local.playAndWipe(
        decryptedLocalPath,
        onWiped: () async {
          // Request remote deletion via Firestore flag
          await _remote.requestRemoteWipe(message.coupleId, message.id);
          Log.i(_tag, '✅ Local wipe + remote wipe requested: ${message.id}');
        },
      );
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'playAndWipe failed', error: e, stack: st);
      return Left(PlaybackFailure(e.toString()));
    }
  }

  // ── Incoming stream ───────────────────────────────────────────────────────

  @override
  Stream<Either<RecordingFailure, WhisperMessage>> watchIncomingWhispers({
    required String myUid,
    required String coupleId,
  }) =>
      _remote
          .watchIncomingWhispers(myUid: myUid, coupleId: coupleId)
          .expand((list) => list)
          .map((data) {
        try {
          return Right<RecordingFailure, WhisperMessage>(WhisperMessage(
            id:              data['id'] as String,
            coupleId:        coupleId,
            fromUid:         data['fromUid']      as String,
            toUid:           data['toUid']        as String,
            storagePath:     data['storagePath']  as String,
            durationSeconds: data['durationSecs'] as int,
            createdAt:       (data['createdAt'] as dynamic).toDate() as DateTime,
            status:          WhisperStatus.received,
          ));
        } catch (e) {
          return Left<RecordingFailure, WhisperMessage>(
            RecordingFailure('Parse error: $e'),
          );
        }
      });

  // ── Remote wipe ───────────────────────────────────────────────────────────

  @override
  Future<void> requestRemoteWipe(WhisperMessage message) =>
      _remote.requestRemoteWipe(message.coupleId, message.id);
}
