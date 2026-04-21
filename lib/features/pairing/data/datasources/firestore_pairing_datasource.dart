// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — firestore_pairing_datasource.dart
//
//  Firestore schema:
//
//  users/{uid}
//    fcmToken:       string
//    publicKey:      string  (RSA JSON)
//    displayName:    string?
//    pairedWith:     string? (partner uid)
//    coupleId:       string?
//    createdAt:      timestamp
//
//  pairs/{code}               ← TTL: 5 minutes, 6 numeric digits
//    initiatorUid:             string
//    initiatorFcmToken:        string
//    initiatorPublicKey:       string
//    createdAt:                timestamp
//    expiresAt:                timestamp
//    status:                   'pending' | 'accepted'
//
//  couples/{coupleId}         ← 1-to-1 lock document
//    user1Uid:                 string
//    user1FcmToken:            string
//    user1PublicKey:           string
//    user2Uid:                 string
//    user2FcmToken:            string
//    user2PublicKey:           string
//    createdAt:                timestamp
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';
import '../models/pair_session_model.dart';
import '../models/user_profile_model.dart';

class FirestorePairingDataSource {
  FirestorePairingDataSource({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const _tag = 'FirestorePairingDS';
  final FirebaseFirestore _db;

  // ── Collection references ────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(AppConstants.colUsers);
  CollectionReference<Map<String, dynamic>> get _pairs =>
      _db.collection(AppConstants.colPairs);
  CollectionReference<Map<String, dynamic>> get _couples =>
      _db.collection('couples');

  // ── FCM Token ─────────────────────────────────────────────────────────────

  Future<String?> getFcmToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    Log.i(_tag, 'FCM token obtained: ${token?.substring(0, 12)}...');
    return token;
  }

  // ── User Profile ──────────────────────────────────────────────────────────

  Future<void> saveUserProfile(UserProfileModel profile) async {
    await _users.doc(profile.uid).set(profile.toFirestore(), SetOptions(merge: true));
    Log.i(_tag, 'User profile saved: ${profile.uid}');
  }

  Stream<UserProfileModel?> watchUserProfile(String uid) =>
      _users.doc(uid).snapshots().map((snap) =>
          snap.exists ? UserProfileModel.fromFirestore(snap) : null);

  Future<UserProfileModel?> getUserProfile(String uid) async {
    final snap = await _users.doc(uid).get();
    return snap.exists ? UserProfileModel.fromFirestore(snap) : null;
  }

  // ── Pair Code ─────────────────────────────────────────────────────────────

  /// Generates a 6-digit code, writes it to `pairs/{code}`, returns the code.
  Future<String> generatePairCode({
    required String initiatorUid,
    required String initiatorFcmToken,
    required String initiatorPublicKeyJson,
  }) async {
    // Verify this user is not already paired.
    final existingProfile = await getUserProfile(initiatorUid);
    if (existingProfile != null && existingProfile.pairedWith != null) {
      throw Exception('Device is already paired. Unpair first.');
    }

    final code = _generateSixDigitCode();
    final now = DateTime.now();
    final expiresAt = now.add(AppConstants.pairCodeExpiry);

    await _pairs.doc(code).set({
      AppConstants.fieldFcmToken:   initiatorFcmToken, // legacy key for FCM
      'initiatorUid':              initiatorUid,
      'initiatorFcmToken':         initiatorFcmToken,
      'initiatorPublicKey':        initiatorPublicKeyJson,
      AppConstants.fieldCreatedAt: Timestamp.fromDate(now),
      AppConstants.fieldExpiresAt: Timestamp.fromDate(expiresAt),
      'status':                    'pending',
    });

    Log.i(_tag, 'Pair code $code generated (expires in 5 min)');
    return code;
  }

  /// Validates and consumes a pair code, creating the couples document.
  /// Returns the new [PairSessionModel] on success.
  /// Throws if code is expired, already used, or the initiator/joiner is
  /// already paired (1-to-1 lock enforcement).
  Future<PairSessionModel> acceptPairCode({
    required String code,
    required String joinerUid,
    required String joinerFcmToken,
    required String joinerPublicKeyJson,
  }) async {
    return _db.runTransaction((tx) async {
      // ── Read the pair invitation ────────────────────────────────────
      final pairRef = _pairs.doc(code);
      final pairSnap = await tx.get(pairRef);

      if (!pairSnap.exists) throw Exception('Invalid pair code.');

      final pairData = pairSnap.data()!;
      final expiresAt =
          (pairData[AppConstants.fieldExpiresAt] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        throw Exception('Pair code has expired. Ask your partner to generate a new one.');
      }
      if (pairData['status'] != 'pending') {
        throw Exception('Pair code has already been used.');
      }

      final initiatorUid       = pairData['initiatorUid'] as String;
      final initiatorFcmToken  = pairData['initiatorFcmToken'] as String;
      final initiatorPublicKey = pairData['initiatorPublicKey'] as String;

      if (initiatorUid == joinerUid) {
        throw Exception('You cannot pair with your own device.');
      }

      // ── 1-to-1 Lock: verify neither device is already paired ────────
      final initiatorRef = _users.doc(initiatorUid);
      final joinerRef    = _users.doc(joinerUid);
      final initiatorSnap = await tx.get(initiatorRef);
      final joinerSnap    = await tx.get(joinerRef);

      if (initiatorSnap.exists) {
        final data = initiatorSnap.data()!;
        if (data['pairedWith'] != null && (data['pairedWith'] as String).isNotEmpty) {
          throw Exception('The initiating device is already paired.');
        }
      }
      if (joinerSnap.exists) {
        final data = joinerSnap.data()!;
        if (data['pairedWith'] != null && (data['pairedWith'] as String).isNotEmpty) {
          throw Exception('Your device is already paired. Unpair first.');
        }
      }

      // ── Create the couples document (1-to-1 lock) ───────────────────
      final coupleRef = _couples.doc();
      final now       = DateTime.now();

      final coupleData = {
        'user1Uid':        initiatorUid,
        'user1FcmToken':   initiatorFcmToken,
        'user1PublicKey':  initiatorPublicKey,
        'user2Uid':        joinerUid,
        'user2FcmToken':   joinerFcmToken,
        'user2PublicKey':  joinerPublicKeyJson,
        AppConstants.fieldCreatedAt: Timestamp.fromDate(now),
      };
      tx.set(coupleRef, coupleData);

      // ── Update both user profiles ────────────────────────────────────
      tx.update(initiatorRef, {
        'pairedWith': joinerUid,
        'coupleId':   coupleRef.id,
      });
      tx.set(joinerRef, {
        'uid':        joinerUid,
        'fcmToken':   joinerFcmToken,
        'publicKey':  joinerPublicKeyJson,
        'pairedWith': initiatorUid,
        'coupleId':   coupleRef.id,
        AppConstants.fieldCreatedAt: Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      // ── Mark the pair code as consumed ───────────────────────────────
      tx.update(pairRef, {'status': 'accepted'});

      Log.i(_tag, 'Pair handshake complete: couple=${coupleRef.id}');

      return PairSessionModel(
        coupleId:            coupleRef.id,
        user1Uid:            initiatorUid,
        user1FcmToken:       initiatorFcmToken,
        user1PublicKeyJson:  initiatorPublicKey,
        user2Uid:            joinerUid,
        user2FcmToken:       joinerFcmToken,
        user2PublicKeyJson:  joinerPublicKeyJson,
        createdAt:           now,
      );
    });
  }

  /// Reads the couple document for this user if they are already paired.
  Future<PairSessionModel?> getActivePairSession(String uid) async {
    final profile = await getUserProfile(uid);
    if (profile?.coupleId == null) return null;
    final snap = await _couples.doc(profile!.coupleId!).get();
    return snap.exists ? PairSessionModel.fromFirestore(snap) : null;
  }

  /// Deletes the couple + clears both user pairedWith fields.
  Future<void> unpair(String coupleId, String uid1, String uid2) async {
    final batch = _db.batch();
    batch.delete(_couples.doc(coupleId));
    batch.update(_users.doc(uid1), {'pairedWith': FieldValue.delete(), 'coupleId': FieldValue.delete()});
    batch.update(_users.doc(uid2), {'pairedWith': FieldValue.delete(), 'coupleId': FieldValue.delete()});
    await batch.commit();
    Log.w(_tag, 'Unpaired: couple=$coupleId');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  String _generateSixDigitCode() {
    final rng = math.Random.secure();
    // Generate 6 digits, zero-padded, guaranteed no leading zero collisions.
    return List.generate(AppConstants.pairCodeLength, (_) => rng.nextInt(10))
        .join();
  }
}
