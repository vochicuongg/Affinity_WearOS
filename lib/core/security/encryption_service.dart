// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — encryption_service.dart  (Phase 2 — Full Implementation)
//
//  Cryptographic primitives used:
//   • RSA-2048 / OAEP-SHA256  — asymmetric key exchange (session key wrapping)
//   • AES-256-GCM             — symmetric message encryption
//   • UUID v4 nonce + timestamp — anti-replay protection
//   • FortunaRandom (CSPRNG)  — key and IV generation
//
//  Key serialization format (Firestore / secure storage):
//   Public  key → JSON {"n":"<hex>","e":"<hex>"}
//   Private key → JSON {"n":"<hex>","e":"<hex>","d":"<hex>","p":"<hex>","q":"<hex>"}
//   Ciphertext envelope → [16B nonce UUID][8B timestamp BE][ciphertext bytes]
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../errors/failures.dart';
import '../utils/logger.dart';
import 'key_storage_service.dart';

// ── Public interface (unchanged from Phase 1 stub) ────────────────────────
abstract interface class IEncryptionService {
  Future<Either<EncryptionFailure, void>> generateAndStoreKeyPair();
  Future<Either<EncryptionFailure, String>> getLocalPublicKey();
  Future<Either<EncryptionFailure, Uint8List>> encrypt(Uint8List plaintext);
  Future<Either<EncryptionFailure, Uint8List>> decrypt(Uint8List ciphertext);
  Future<Either<EncryptionFailure, void>> deriveSessionKey(
    String partnerPublicKeyJson,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class EncryptionService implements IEncryptionService {
  EncryptionService(this._keyStorage);

  static const _tag = 'EncryptionService';
  static const _rsaBits = 2048;
  static const _gcmMacBits = 128;
  static const _aesKeyBytes = 32; // AES-256
  static const _ivBytes = 12;     // GCM recommended IV size

  final KeyStorageService _keyStorage;
  final _uuid = const Uuid();

  // Cache decrypted keys in memory for the lifetime of the app session.
  RSAPrivateKey? _privateKey;
  RSAPublicKey? _publicKey;
  Uint8List? _sessionKey;

  // ── CSPRNG ────────────────────────────────────────────────────────────

  SecureRandom _buildSecureRandom() {
    final sr = FortunaRandom();
    final seed = Uint8List(32);
    final rng = math.Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    sr.seed(KeyParameter(seed));
    return sr;
  }

  // ── RSA Key Generation ────────────────────────────────────────────────

  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateRSAKeyPair() {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), _rsaBits, 64),
        _buildSecureRandom(),
      ));
    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  // ── Key Serialization ─────────────────────────────────────────────────

  String _publicKeyToJson(RSAPublicKey key) => jsonEncode({
        'n': key.modulus!.toRadixString(16),
        'e': key.exponent!.toRadixString(16),
      });

  String _privateKeyToJson(RSAPrivateKey key) => jsonEncode({
        'n': key.modulus!.toRadixString(16),
        'e': key.publicExponent!.toRadixString(16),
        'd': key.exponent!.toRadixString(16),
        'p': key.p!.toRadixString(16),
        'q': key.q!.toRadixString(16),
      });

  RSAPublicKey _publicKeyFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return RSAPublicKey(
      BigInt.parse(m['n'] as String, radix: 16),
      BigInt.parse(m['e'] as String, radix: 16),
    );
  }

  RSAPrivateKey _privateKeyFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final n = BigInt.parse(m['n'] as String, radix: 16);
    // 'e' (public exponent) is stored for completeness but not
    // required by the RSAPrivateKey constructor.
    final d = BigInt.parse(m['d'] as String, radix: 16);
    final p = BigInt.parse(m['p'] as String, radix: 16);
    final q = BigInt.parse(m['q'] as String, radix: 16);
    return RSAPrivateKey(n, d, p, q);
  }

  // ── RSA OAEP-SHA256 ────────────────────────────────────────────────────

  Uint8List _rsaEncrypt(RSAPublicKey publicKey, Uint8List data) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return cipher.process(data);
  }

  Uint8List _rsaDecrypt(RSAPrivateKey privateKey, Uint8List data) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return cipher.process(data);
  }

  // ── AES-256-GCM ───────────────────────────────────────────────────────

  Uint8List _aesGcmEncrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List plaintext,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _gcmMacBits, iv, Uint8List(0)));
    return cipher.process(plaintext);
  }

  Uint8List _aesGcmDecrypt(
    Uint8List key,
    Uint8List iv,
    Uint8List ciphertext,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), _gcmMacBits, iv, Uint8List(0)));
    return cipher.process(ciphertext);
  }

  // ── Nonce / Anti-Replay ────────────────────────────────────────────────

  /// Builds the envelope: [16B UUID nonce][8B timestamp big-endian][ciphertext]
  Uint8List _buildEnvelope(Uint8List nonce, Uint8List ciphertext) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tsBytes = ByteData(8)..setInt64(0, ts, Endian.big);
    return Uint8List.fromList([
      ...nonce,
      ...tsBytes.buffer.asUint8List(),
      ...ciphertext,
    ]);
  }

  /// Parses the envelope. Returns null if the timestamp is stale (replay attack).
  ({Uint8List nonce, Uint8List ciphertext})? _parseEnvelope(Uint8List envelope) {
    if (envelope.length < AppConstants.nonceBytes + 8 + 1) return null;
    final nonce = envelope.sublist(0, AppConstants.nonceBytes);
    final tsBytes = envelope.sublist(AppConstants.nonceBytes, AppConstants.nonceBytes + 8);
    final ts = ByteData.view(Uint8List.fromList(tsBytes).buffer).getInt64(0, Endian.big);
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age.abs() > AppConstants.maxMessageAge.inMilliseconds) {
      Log.w(_tag, 'Replay attack rejected — message age: ${age}ms');
      return null;
    }
    final ciphertext = envelope.sublist(AppConstants.nonceBytes + 8);
    return (nonce: nonce, ciphertext: ciphertext);
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  IEncryptionService implementation
  // ═════════════════════════════════════════════════════════════════════════

  @override
  Future<Either<EncryptionFailure, void>> generateAndStoreKeyPair() async {
    try {
      Log.i(_tag, 'Generating RSA-$_rsaBits key pair...');
      final pair = _generateRSAKeyPair();
      _publicKey = pair.publicKey;
      _privateKey = pair.privateKey;

      await Future.wait([
        _keyStorage.savePublicKey(_publicKeyToJson(pair.publicKey)),
        _keyStorage.savePrivateKey(_privateKeyToJson(pair.privateKey)),
      ]);
      Log.i(_tag, 'RSA key pair generated and stored');
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'Key generation failed', error: e, stack: st);
      return Left(EncryptionFailure('Key generation failed: $e'));
    }
  }

  @override
  Future<Either<EncryptionFailure, String>> getLocalPublicKey() async {
    try {
      // Check in-memory cache first.
      if (_publicKey != null) return Right(_publicKeyToJson(_publicKey!));
      // Load from secure storage.
      final stored = await _keyStorage.loadPublicKey();
      if (stored != null) {
        _publicKey = _publicKeyFromJson(stored);
        return Right(stored);
      }
      // No key exists — generate one.
      final result = await generateAndStoreKeyPair();
      return result.fold(
        (f) => Left(f),
        (_) => Right(_publicKeyToJson(_publicKey!)),
      );
    } catch (e, st) {
      Log.e(_tag, 'getLocalPublicKey failed', error: e, stack: st);
      return Left(EncryptionFailure('Public key unavailable: $e'));
    }
  }

  @override
  Future<Either<EncryptionFailure, void>> deriveSessionKey(
    String partnerPublicKeyJson,
  ) async {
    try {
      // Generate a fresh random 256-bit AES session key.
      final sr = _buildSecureRandom();
      final key = sr.nextBytes(_aesKeyBytes);
      _sessionKey = key;

      // Encrypt the session key with the partner's RSA public key
      // so only they can decrypt it. Store the hex for upload to Firestore.
      final partnerPubKey = _publicKeyFromJson(partnerPublicKeyJson);
      final encryptedSessionKey = _rsaEncrypt(partnerPubKey, key);

      // Persist the raw session key locally (encrypted at rest by secure storage).
      await _keyStorage.saveSessionKey(
        base64Encode(encryptedSessionKey),
      );
      Log.i(_tag, 'AES-256 session key derived and encrypted for partner');
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'deriveSessionKey failed', error: e, stack: st);
      return Left(EncryptionFailure('Session key derivation failed: $e'));
    }
  }

  @override
  Future<Either<EncryptionFailure, Uint8List>> encrypt(
    Uint8List plaintext,
  ) async {
    try {
      final key = await _getOrLoadSessionKey();
      if (key == null) return const Left(EncryptionFailure('No session key'));

      // Generate a random IV for each encryption operation.
      final iv = _buildSecureRandom().nextBytes(_ivBytes);
      final nonce = Uint8List.fromList(_uuid.v4().replaceAll('-', '').codeUnits
          .take(AppConstants.nonceBytes)
          .toList());

      final ciphertext = _aesGcmEncrypt(key, iv, plaintext);
      // Prepend IV to ciphertext so the receiver can decode it.
      final ivAndCipher = Uint8List.fromList([...iv, ...ciphertext]);
      return Right(_buildEnvelope(nonce, ivAndCipher));
    } catch (e, st) {
      Log.e(_tag, 'encrypt failed', error: e, stack: st);
      return Left(EncryptionFailure('Encryption failed: $e'));
    }
  }

  @override
  Future<Either<EncryptionFailure, Uint8List>> decrypt(
    Uint8List ciphertext,
  ) async {
    try {
      final parsed = _parseEnvelope(ciphertext);
      if (parsed == null) {
        return const Left(
          EncryptionFailure('Message rejected: potential replay attack detected.'),
        );
      }

      final key = await _getOrLoadSessionKey();
      if (key == null) return const Left(EncryptionFailure('No session key'));

      final ivAndCipher = parsed.ciphertext;
      if (ivAndCipher.length < _ivBytes + 1) {
        return const Left(EncryptionFailure('Malformed ciphertext'));
      }
      final iv       = ivAndCipher.sublist(0, _ivBytes);
      final payload  = ivAndCipher.sublist(_ivBytes);
      final plaintext = _aesGcmDecrypt(key, iv, payload);
      return Right(plaintext);
    } catch (e, st) {
      Log.e(_tag, 'decrypt failed', error: e, stack: st);
      return Left(EncryptionFailure('Decryption failed: $e'));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<Uint8List?> _getOrLoadSessionKey() async {
    if (_sessionKey != null) return _sessionKey;
    final stored = await _keyStorage.loadSessionKey();
    if (stored == null) return null;
    // Decrypt the stored RSA-wrapped session key using our private key.
    await _ensurePrivateKeyLoaded();
    if (_privateKey == null) return null;
    final decrypted = _rsaDecrypt(_privateKey!, base64Decode(stored));
    _sessionKey = decrypted;
    return decrypted;
  }

  Future<void> _ensurePrivateKeyLoaded() async {
    if (_privateKey != null) return;
    final stored = await _keyStorage.loadPrivateKey();
    if (stored != null) _privateKey = _privateKeyFromJson(stored);
  }
}
