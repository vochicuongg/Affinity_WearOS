// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — mood_remote_datasource.dart
//
//  Firestore schema:
//  couples/{coupleId}/moods/{uid}
//    ciphertext:  string  (base64 AES-GCM encrypted JSON {mood: id, ts: ms, nonce: uuid})
//    updatedAt:   timestamp
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/mood_state.dart';

class MoodRemoteDataSource {
  MoodRemoteDataSource({
    FirebaseFirestore? firestore,
    required IEncryptionService encryption,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _encryption = encryption;

  static const _tag = 'MoodRemoteDS';
  final FirebaseFirestore _db;
  final IEncryptionService _encryption;
  final _uuid = const Uuid();

  DocumentReference<Map<String, dynamic>> _moodDoc(
    String coupleId,
    String uid,
  ) =>
      _db.collection('couples').doc(coupleId).collection('moods').doc(uid);

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> updateMood({
    required String uid,
    required String coupleId,
    required AffinityMood mood,
  }) async {
    final nonce = _uuid.v4();
    final ts    = DateTime.now().millisecondsSinceEpoch;

    final plaintext = utf8.encode(jsonEncode({
      'mood':  mood.id,
      'nonce': nonce,
      'ts':    ts,
    }));

    final encResult =
        await _encryption.encrypt(Uint8List.fromList(plaintext));
    final ciphertext = encResult.fold(
      (f) => throw Exception('Mood encryption failed: ${f.message}'),
      base64Encode,
    );

    await _moodDoc(coupleId, uid).set({
      'ciphertext': ciphertext,
      AppConstants.fieldCreatedAt: Timestamp.fromMillisecondsSinceEpoch(ts),
    });

    Log.i(_tag, 'Mood updated: ${mood.label} for uid=$uid coupleId=$coupleId');
  }

  // ── Read / stream partner mood ────────────────────────────────────────────

  Stream<MoodState?> watchPartnerMood(String partnerUid, String coupleId) =>
      _moodDoc(coupleId, partnerUid).snapshots().asyncMap((snap) async {
        if (!snap.exists) return null;
        return await _decrypt(snap.data()!, partnerUid, coupleId);
      });

  Future<AffinityMood> getMyMood(String uid, String coupleId) async {
    final snap = await _moodDoc(coupleId, uid).get();
    if (!snap.exists) return AffinityMood.neutral;
    final state = await _decrypt(snap.data()!, uid, coupleId);
    return state?.mood ?? AffinityMood.neutral;
  }

  // ── Decryption ────────────────────────────────────────────────────────────

  Future<MoodState?> _decrypt(
    Map<String, dynamic> data,
    String uid,
    String coupleId,
  ) async {
    try {
      final bytes = base64Decode(data['ciphertext'] as String);
      final result = await _encryption.decrypt(Uint8List.fromList(bytes));
      return result.fold(
        (f) {
          Log.w(_tag, 'Mood decryption failed: ${f.message}');
          return null;
        },
        (plain) {
          final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          return MoodState(
            uid:       uid,
            coupleId:  coupleId,
            mood:      AffinityMoodX.fromId(json['mood'] as String),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(json['ts'] as int),
            ciphertext: data['ciphertext'] as String,
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'Mood decrypt error', error: e, stack: st);
      return null;
    }
  }
}
