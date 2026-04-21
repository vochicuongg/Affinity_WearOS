// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — key_storage_service.dart
//  Secure local key vault using flutter_secure_storage
//  (backed by Android EncryptedSharedPreferences on Wear OS).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';

class KeyStorageService {
  KeyStorageService() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tag = 'KeyStorageService';
  final FlutterSecureStorage _storage;

  // ── RSA Private Key ────────────────────────────────────────────────────

  Future<void> savePrivateKey(String privateKeyJson) async {
    await _storage.write(key: AppConstants.keyRsaPrivate, value: privateKeyJson);
    Log.i(_tag, 'RSA private key saved to EncryptedSharedPreferences');
  }

  Future<String?> loadPrivateKey() =>
      _storage.read(key: AppConstants.keyRsaPrivate);

  // ── RSA Public Key ─────────────────────────────────────────────────────

  Future<void> savePublicKey(String publicKeyJson) async =>
      _storage.write(key: AppConstants.keyRsaPublic, value: publicKeyJson);

  Future<String?> loadPublicKey() =>
      _storage.read(key: AppConstants.keyRsaPublic);

  // ── AES Session Key ────────────────────────────────────────────────────

  Future<void> saveSessionKey(String sessionKeyHex) async =>
      _storage.write(key: AppConstants.keyAesSession, value: sessionKeyHex);

  Future<String?> loadSessionKey() =>
      _storage.read(key: AppConstants.keyAesSession);

  // ── Pair / Partner IDs ─────────────────────────────────────────────────

  Future<void> savePairId(String pairId) =>
      _storage.write(key: AppConstants.keyPairId, value: pairId);

  Future<String?> loadPairId() => _storage.read(key: AppConstants.keyPairId);

  Future<void> savePartnerId(String partnerId) =>
      _storage.write(key: AppConstants.keyPartnerId, value: partnerId);

  Future<String?> loadPartnerId() =>
      _storage.read(key: AppConstants.keyPartnerId);

  // ── Wipe All ───────────────────────────────────────────────────────────

  /// Erases all Affinity keys — called on unpair or off-body lock.
  Future<void> wipeAll() async {
    await _storage.deleteAll();
    Log.w(_tag, 'All keys wiped from secure storage');
  }
}
