// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_remote_datasource.dart
//
//  Firebase Storage + Firestore signaling for Whisper PTT.
//
//  Storage schema:
//    whispers/{coupleId}/{messageId}.enc     ← encrypted audio blob
//
//  Firestore schema:
//    couples/{coupleId}/whispers/{messageId}
//      fromUid:        string
//      toUid:          string
//      toFcmToken:     string
//      storagePath:    string   (Firebase Storage path)
//      durationSecs:   int
//      createdAt:      Timestamp
//      played:         bool     (false → true after playback, triggers CF deletion)
//      wipeRequested:  bool     (true → Cloud Function deletes Storage file)
//
//  Security note:
//   • The Firestore document metadata is E2EE encrypted in the haptic pipeline.
//   • For whispers, only the Storage blob is AES-GCM encrypted.
//   • Firestore metadata (fromUid, storagePath) is cleartext — by design,
//     the server needs storagePath to delete it. fromUid is already in auth.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';


class WhisperRemoteDataSource {
  WhisperRemoteDataSource({
    FirebaseFirestore? firestore,
    FirebaseStorage?   storage,
  })  : _db      = firestore ?? FirebaseFirestore.instance,
        _storage = storage   ?? FirebaseStorage.instance;

  static const _tag = 'WhisperRemoteDS';
  final FirebaseFirestore _db;
  final FirebaseStorage   _storage;

  // ── Storage helpers ───────────────────────────────────────────────────────

  Reference _storageRef(String coupleId, String messageId) =>
      _storage.ref('whispers/$coupleId/$messageId.enc');

  // ── Firestore helpers ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _whispersColl(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('whispers');

  // ── Upload encrypted audio ────────────────────────────────────────────────

  /// Uploads [encryptedBytes] to Firebase Storage.
  /// Returns the Firebase Storage download URL (not needed for download —
  /// we use the storagePath reference directly for security).
  Future<String> uploadEncryptedAudio({
    required String coupleId,
    required String messageId,
    required Uint8List encryptedBytes,
  }) async {
    final ref = _storageRef(coupleId, messageId);

    Log.i(_tag, 'Uploading ${encryptedBytes.length} encrypted bytes → ${ref.fullPath}');

    await ref.putData(
      encryptedBytes,
      SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {
          'encrypted': 'aes-256-gcm',
          'version':   '1',
        },
      ),
    );

    Log.i(_tag, 'Upload complete: ${ref.fullPath}');
    return ref.fullPath;
  }

  // ── Write Firestore signal ────────────────────────────────────────────────

  Future<void> writeWhisperSignal({
    required String messageId,
    required String coupleId,
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String storagePath,
    required int durationSeconds,
  }) async {
    final ts = Timestamp.now();
    await _whispersColl(coupleId).doc(messageId).set({
      'fromUid':       fromUid,
      'toUid':         toUid,
      'toFcmToken':    toFcmToken,
      'storagePath':   storagePath,
      'durationSecs':  durationSeconds,
      AppConstants.fieldCreatedAt: ts,
      'played':        false,
      'wipeRequested': false,
    });
    Log.i(_tag, 'Whisper signal written: $messageId');
  }

  // ── Download encrypted audio ──────────────────────────────────────────────

  Future<Uint8List> downloadEncryptedAudio({
    required String coupleId,
    required String messageId,
  }) async {
    final ref   = _storageRef(coupleId, messageId);
    Log.i(_tag, 'Downloading from ${ref.fullPath}');

    final bytes = await ref.getData();
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Download failed — empty data from ${ref.fullPath}');
    }

    Log.i(_tag, 'Downloaded ${bytes.length} bytes');
    return bytes;
  }

  // ── Request remote wipe ───────────────────────────────────────────────────

  /// Sets `played: true` and `wipeRequested: true` on the Firestore doc.
  /// A Cloud Function listens for `wipeRequested: true` and deletes the
  /// Firebase Storage file, then deletes this Firestore document.
  Future<void> requestRemoteWipe(String coupleId, String messageId) async {
    await _whispersColl(coupleId).doc(messageId).update({
      'played':        true,
      'wipeRequested': true,
      'playedAt':      Timestamp.now(),
    });
    Log.i(_tag, '🗑 Remote wipe requested: $messageId');
  }

  // ── Stream incoming whispers ──────────────────────────────────────────────

  /// Returns a stream of new unplayed whisper documents targeted at [myUid].
  Stream<List<Map<String, dynamic>>> watchIncomingWhispers({
    required String myUid,
    required String coupleId,
  }) =>
      _whispersColl(coupleId)
          .where('toUid',  isEqualTo: myUid)
          .where('played', isEqualTo: false)
          .orderBy(AppConstants.fieldCreatedAt, descending: false)
          .snapshots()
          .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
}
