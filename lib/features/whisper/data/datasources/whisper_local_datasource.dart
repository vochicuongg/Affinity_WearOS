// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_local_datasource.dart
//
//  Audio E2EE encryption pipeline:
//
//  SEND:
//    ①  Raw recording bytes read from temp .m4a file
//    ②  EncryptionService.encrypt(bytes) → AES-256-GCM
//        Internally: generates fresh 12-byte random IV per call
//        Output format: [4B length][12B IV][16B tag][ciphertext]
//    ③  Write .enc file to whisper temp dir
//    ④  SecureWipe the original .m4a
//
//  RECEIVE:
//    ①  Download .enc bytes from Firebase Storage
//    ②  EncryptionService.decrypt(bytes) → plaintext audio bytes
//    ③  Write decrypted bytes to temp .m4a file
//    ④  Play at whisper volume (35%)
//    ⑤  SecureWipe the decrypted .m4a after playback
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../../core/audio/audio_service.dart';
import '../../../../core/audio/secure_wipe_service.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/utils/logger.dart';

class WhisperLocalDataSource {
  WhisperLocalDataSource({
    required IEncryptionService encryption,
    required AudioService audioService,
    required SecureWipeService wipeService,
  })  : _encryption = encryption,
        _audio = audioService,
        _wipe = wipeService;

  static const _tag = 'WhisperLocalDS';
  final IEncryptionService _encryption;
  final AudioService _audio;
  final SecureWipeService _wipe;

  // ── Temp directory ────────────────────────────────────────────────────────

  Future<Directory> _whisperTempDir() async {
    final base = await getTemporaryDirectory();
    final dir  = Directory('${base.path}/affinity_whispers');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  // ── Recording ─────────────────────────────────────────────────────────────

  Future<String> tempRecordingPath(String messageId) async {
    final dir = await _whisperTempDir();
    return '${dir.path}/$messageId.m4a';
  }

  Future<String> startRecording(String messageId) async {
    final path = await tempRecordingPath(messageId);
    await _audio.startRecording(path);
    Log.i(_tag, 'Recording → $path');
    return path;
  }

  Future<String?> stopRecording() => _audio.stopRecording();

  Stream<double> get amplitudeStream => _audio.amplitudeStream;

  // ── Encrypt raw audio file ────────────────────────────────────────────────

  /// Reads [rawPath], encrypts with AES-256-GCM, writes to [rawPath].enc,
  /// then secure-wipes [rawPath].
  ///
  /// Returns the path of the encrypted .enc file.
  Future<String> encryptAudioFile(String rawPath) async {
    final rawFile = File(rawPath);
    if (!rawFile.existsSync()) {
      throw Exception('Raw recording not found: $rawPath');
    }

    final rawBytes = await rawFile.readAsBytes();
    Log.i(_tag, 'Encrypting ${rawBytes.length} bytes of audio');

    final encResult = await _encryption.encrypt(Uint8List.fromList(rawBytes));
    final encBytes  = encResult.fold(
      (f) => throw Exception('Audio encryption failed: ${f.message}'),
      (b) => b,
    );

    final encPath = '$rawPath.enc';
    await File(encPath).writeAsBytes(encBytes, flush: true);
    Log.i(_tag, 'Encrypted file written: $encPath (${encBytes.length} bytes)');

    // Secure-wipe the unencrypted recording
    await _wipe.wipePath(rawPath);
    Log.i(_tag, 'Original recording wiped');

    return encPath;
  }

  // ── Decrypt received audio ────────────────────────────────────────────────

  /// Decrypts [encryptedBytes] and writes the result to a temp .m4a file.
  /// Returns the path of the decrypted file (must be wiped after playback).
  Future<String> decryptAudioBytes(
    Uint8List encryptedBytes,
    String messageId,
  ) async {
    Log.i(_tag, 'Decrypting ${encryptedBytes.length} bytes');

    final decResult = await _encryption.decrypt(encryptedBytes);
    final rawBytes  = decResult.fold(
      (f) => throw Exception('Audio decryption failed: ${f.message}'),
      (b) => b,
    );

    final dir  = await _whisperTempDir();
    final path = '${dir.path}/${messageId}_rx.m4a';
    await File(path).writeAsBytes(rawBytes, flush: true);

    Log.i(_tag, 'Decrypted audio written: $path (${rawBytes.length} bytes)');
    return path;
  }

  // ── Playback + wipe ───────────────────────────────────────────────────────

  /// Plays decrypted audio at whisper volume, then secure-wipes it.
  Future<void> playAndWipe(String decryptedPath, {VoidCallback? onWiped}) async {
    await _audio.playWhisper(
      decryptedPath,
      onComplete: () async {
        Log.i(_tag, 'Playback complete → secure wiping $decryptedPath');
        await _wipe.wipePath(decryptedPath);
        onWiped?.call();
      },
    );
  }

  Future<void> stopPlayback() => _audio.stopPlayback();

  // ── Wipe entire whisper temp dir ──────────────────────────────────────────

  Future<void> wipeAllTempFiles() async {
    final dir = await _whisperTempDir();
    final count = await _wipe.wipeDirectory(dir, deleteIfEmpty: true);
    Log.i(_tag, 'Wiped $count temp whisper files');
  }
}
