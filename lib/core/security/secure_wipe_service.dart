// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — secure_wipe_service.dart
//  Phase 1 STUB — Zero-byte overwrite of ephemeral audio files before deletion.
//  Full implementation in Phase 5 (Audio Love Notes).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:typed_data';
import 'package:dartz/dartz.dart';
import '../errors/failures.dart';
import '../utils/logger.dart';

abstract interface class ISecureWipeService {
  /// Overwrites [file] with zeroes then deletes it.
  /// Satisfies the "Privacy by Design" requirement for ephemeral voice notes.
  Future<Either<SecureWipeFailure, void>> wipeFile(File file);
}

final class SecureWipeService implements ISecureWipeService {
  const SecureWipeService();

  static const String _tag = 'SecureWipeService';

  @override
  Future<Either<SecureWipeFailure, void>> wipeFile(File file) async {
    try {
      if (!await file.exists()) return const Right(null);

      final int size = await file.length();
      // Overwrite with zero-bytes in a single pass.
      final Uint8List zeros = Uint8List(size);
      await file.writeAsBytes(zeros, flush: true);

      await file.delete();
      Log.i(_tag, 'Secure wipe complete: ${file.path} ($size bytes zeroed)');
      return const Right(null);
    } catch (e, st) {
      Log.e(_tag, 'Wipe failed for ${file.path}', error: e, stack: st);
      return Left(SecureWipeFailure('Secure wipe failed: $e'));
    }
  }
}
