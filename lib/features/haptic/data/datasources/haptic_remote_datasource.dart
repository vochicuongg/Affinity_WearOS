// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_remote_datasource.dart
//
//  Firestore schema for haptics:
//
//  couples/{coupleId}/signals/{signalId}
//    fromUid:     string
//    toUid:       string
//    toFcmToken:  string
//    signal:      string   (LoveSignal.id)
//    ciphertext:  string   (base64 AES-GCM encrypted payload)
//    timestamp:   timestamp
//    played:      bool
//
//  The Cloud Function (fcm_handler.dart inline docs) listens to this
//  collection and pushes FCM to `toFcmToken`.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/haptic/haptic_service.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/haptic_signal.dart';

class HapticRemoteDataSource {
  HapticRemoteDataSource({
    FirebaseFirestore? firestore,
    required IEncryptionService encryption,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _encryption = encryption;

  static const _tag = 'HapticRemoteDS';
  final FirebaseFirestore _db;
  final IEncryptionService _encryption;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> _signals(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('signals');

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> sendSignal({
    required String fromUid,
    required String toUid,
    required String toFcmToken,
    required String coupleId,
    required LoveSignal signal,
    List<int>? customPattern,
  }) async {
    final pattern = customPattern ?? signal.pattern;
    final nonce   = _uuid.v4();
    final ts      = DateTime.now().millisecondsSinceEpoch;

    // ── Build plaintext payload ──────────────────────────────────────────
    final plaintext = utf8.encode(jsonEncode({
      'signal':  signal.id,
      'pattern': pattern,
      'nonce':   nonce,
      'ts':      ts,
    }));

    // ── Encrypt with AES-256-GCM session key ───────────────────────────
    final encResult =
        await _encryption.encrypt(Uint8List.fromList(plaintext));

    final ciphertext = encResult.fold(
      (f) => throw Exception('Encryption failed: ${f.message}'),
      (bytes) => base64Encode(bytes),
    );

    // ── Write to Firestore ─────────────────────────────────────────────
    final signalId = _uuid.v4();
    await _signals(coupleId).doc(signalId).set({
      'fromUid':    fromUid,
      'toUid':      toUid,
      'toFcmToken': toFcmToken,
      'signal':     signal.id,
      'ciphertext': ciphertext,
      AppConstants.fieldCreatedAt: Timestamp.fromMillisecondsSinceEpoch(ts),
      'played':     false,
    });

    Log.i(
      _tag,
      'Haptic signal sent: ${signal.displayName} → $toUid '
      '(coupleId=$coupleId, signalId=$signalId)',
    );
  }

  // ── Receive Stream ────────────────────────────────────────────────────────

  /// Streams unplayed signals addressed to [uid] in real time.
  Stream<HapticSignal?> watchIncomingSignals(String uid, String coupleId) =>
      _signals(coupleId)
          .where('toUid', isEqualTo: uid)
          .where('played', isEqualTo: false)
          .orderBy(AppConstants.fieldCreatedAt, descending: true)
          .limit(1)
          .snapshots()
          .asyncMap((snap) async {
        if (snap.docs.isEmpty) return null;
        final doc = snap.docs.first;
        return await _decryptSignal(doc);
      });

  // ── Mark Played ───────────────────────────────────────────────────────────

  Future<void> markPlayed(String signalId, String coupleId) async {
    await _signals(coupleId).doc(signalId).update({'played': true});
    Log.d(_tag, 'Signal $signalId marked as played');
  }

  // ── Decryption ────────────────────────────────────────────────────────────

  Future<HapticSignal?> _decryptSignal(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    try {
      final d = doc.data();
      final ciphertextB64 = d['ciphertext'] as String;
      final cipherbytes   = base64Decode(ciphertextB64);

      // Decrypt
      final decResult = await _encryption.decrypt(Uint8List.fromList(cipherbytes));
      return decResult.fold(
        (f) {
          Log.w(_tag, '⛔ Decryption failed for signal ${doc.id}: ${f.message}');
          return null;
        },
        (plainbytes) {
          final json     = jsonDecode(utf8.decode(plainbytes)) as Map<String, dynamic>;
          final signalId = json['signal'] as String? ?? 'custom';
          final ts       = json['ts'] as int? ?? 0;
          final nonce    = json['nonce'] as String? ?? '';
          final age      = DateTime.now().millisecondsSinceEpoch - ts;

          // Anti-replay log
          if (age.abs() > AppConstants.maxMessageAge.inMilliseconds) {
            Log.w(
              _tag,
              '⛔ Anti-Replay REJECTED signal ${doc.id} '
              '— age: ${age}ms, nonce: $nonce',
            );
            return null;
          }
          Log.i(
            _tag,
            '✅ Anti-Replay PASSED signal ${doc.id} '
            '— age: ${age}ms, nonce: $nonce',
          );

          final rawPattern = json['pattern'];
          final pattern = rawPattern is List
              ? rawPattern.cast<int>()
              : LoveSignal.values
                  .firstWhere((s) => s.id == signalId,
                      orElse: () => LoveSignal.heartbeat)
                  .pattern;

          final signal = LoveSignal.values.firstWhere(
            (s) => s.id == signalId,
            orElse: () => LoveSignal.custom,
          );

          return HapticSignal(
            id:         doc.id,
            fromUid:    d['fromUid'] as String,
            toUid:      d['toUid'] as String,
            signal:     signal,
            pattern:    pattern,
            ciphertext: ciphertextB64,
            nonce:      nonce,
            timestamp:  (d[AppConstants.fieldCreatedAt] as Timestamp).toDate(),
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'Signal decryption error for ${doc.id}', error: e, stack: st);
      return null;
    }
  }
}
