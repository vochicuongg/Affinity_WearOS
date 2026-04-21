// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — proximity_remote_datasource.dart
//
//  Firestore schema:
//  couples/{coupleId}/locations/{uid}
//    ciphertext:  string  (base64 AES-GCM encrypted JSON {lat, lon, acc, ts, nonce})
//    updatedAt:   timestamp
//
//  PRIVACY: Raw coordinates are NEVER written. Only post-fuzz + AES-GCM ciphertext.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/location/location_service.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/utils/logger.dart';

class ProximityRemoteDataSource {
  ProximityRemoteDataSource({
    FirebaseFirestore? firestore,
    required IEncryptionService encryption,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _encryption = encryption;

  static const _tag = 'ProximityRemoteDS';
  final FirebaseFirestore _db;
  final IEncryptionService _encryption;
  final _uuid = const Uuid();

  DocumentReference<Map<String, dynamic>> _locationDoc(
    String coupleId,
    String uid,
  ) =>
      _db.collection('couples').doc(coupleId).collection('locations').doc(uid);

  // ── Upload encrypted fuzzed location ──────────────────────────────────────

  Future<void> uploadLocation({
    required String uid,
    required String coupleId,
    required FuzzedLocation location,
  }) async {
    final nonce = _uuid.v4();
    final payload = {
      ...location.toJson(),
      'nonce': nonce,
    };

    final plaintext = utf8.encode(jsonEncode(payload));
    final encResult = await _encryption.encrypt(Uint8List.fromList(plaintext));
    final ciphertext = encResult.fold(
      (f) => throw Exception('Location encryption failed: ${f.message}'),
      base64Encode,
    );

    await _locationDoc(coupleId, uid).set({
      'ciphertext': ciphertext,
      AppConstants.fieldCreatedAt: Timestamp.fromMillisecondsSinceEpoch(
        location.timestamp.millisecondsSinceEpoch,
      ),
    });

    Log.d(
      _tag,
      'Encrypted location uploaded for uid=$uid '
      '(fuzzed: ${location.lat.toStringAsFixed(4)}, ${location.lon.toStringAsFixed(4)})',
    );
  }

  // ── Read partner location (single) ────────────────────────────────────────

  Future<FuzzedLocation?> getPartnerLocation({
    required String partnerUid,
    required String coupleId,
  }) async {
    final snap = await _locationDoc(coupleId, partnerUid).get();
    if (!snap.exists) return null;
    return await _decrypt(snap.data()!);
  }

  // ── Stream partner location ───────────────────────────────────────────────

  Stream<FuzzedLocation?> watchPartnerLocation({
    required String partnerUid,
    required String coupleId,
  }) =>
      _locationDoc(coupleId, partnerUid)
          .snapshots()
          .asyncMap((snap) async {
        if (!snap.exists) return null;
        return await _decrypt(snap.data()!);
      });

  // ── Decryption ────────────────────────────────────────────────────────────

  Future<FuzzedLocation?> _decrypt(Map<String, dynamic> data) async {
    try {
      final bytes  = base64Decode(data['ciphertext'] as String);
      final result = await _encryption.decrypt(Uint8List.fromList(bytes));
      return result.fold(
        (f) {
          Log.w(_tag, 'Location decryption failed: ${f.message}');
          return null;
        },
        (plain) {
          final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          return FuzzedLocation.fromJson(json);
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'Location decrypt error', error: e, stack: st);
      return null;
    }
  }
}
