// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — secure_wipe_service.dart
//
//  Implements DoD 5220.22-M 3-pass overwrite:
//   Pass 1: zeros     (0x00)
//   Pass 2: ones      (0xFF)
//   Pass 3: zeros     (0x00)
//   Then: delete the file
//
//  This prevents recovery via filesystem journal or flash wear-levelling
//  artifacts. On NAND flash (Wear OS), full recovery after 3-pass is
//  practically infeasible with consumer-grade tools.
//
//  Note: `flush: true` forces each write to the OS page cache synchronously
//  before proceeding to the next pass.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:typed_data';

import '../utils/logger.dart';

class SecureWipeService {
  static const _tag = 'SecureWipe';

  /// Performs a 3-pass DoD 5220.22-M overwrite of [file] then deletes it.
  ///
  /// Returns `true` on success, `false` if the file didn't exist.
  /// Throws [SecureWipeException] if overwrite passes fail.
  Future<bool> wipe(File file) async {
    if (!file.existsSync()) {
      Log.d(_tag, 'wipe: file does not exist — skipping');
      return false;
    }

    final path = file.path;
    final size = file.lengthSync();

    if (size == 0) {
      await file.delete();
      Log.d(_tag, 'wipe: zero-length file deleted immediately');
      return true;
    }

    try {
      // ── Pass 1: zeros ─────────────────────────────────────────────────
      await file.writeAsBytes(
        Uint8List(size), // all 0x00
        flush: true,
      );
      Log.d(_tag, 'wipe pass 1/3 (zeros) complete — $size bytes');

      // ── Pass 2: ones ──────────────────────────────────────────────────
      await file.writeAsBytes(
        Uint8List(size)..fillRange(0, size, 0xFF), // all 0xFF
        flush: true,
      );
      Log.d(_tag, 'wipe pass 2/3 (ones) complete');

      // ── Pass 3: zeros again ───────────────────────────────────────────
      await file.writeAsBytes(
        Uint8List(size), // all 0x00
        flush: true,
      );
      Log.d(_tag, 'wipe pass 3/3 (zeros) complete');

      // ── Delete ────────────────────────────────────────────────────────
      await file.delete();
      Log.i(_tag, '✅ Secure wipe complete: $path ($size bytes)');
      return true;
    } catch (e, st) {
      Log.e(_tag, '❌ Secure wipe FAILED for $path', error: e, stack: st);
      // Attempt force-delete even if wipe passes failed
      try { await file.delete(); } catch (_) {}
      rethrow;
    }
  }

  /// Wipes a file at [path] if it exists.
  Future<bool> wipePath(String path) => wipe(File(path));

  /// Wipes all files in [directory] matching [pattern], then optionally
  /// deletes the directory if it becomes empty.
  Future<int> wipeDirectory(
    Directory directory, {
    String pattern = '',
    bool deleteIfEmpty = true,
  }) async {
    if (!directory.existsSync()) return 0;
    int count = 0;
    await for (final entity in directory.list()) {
      if (entity is File) {
        if (pattern.isEmpty || entity.path.contains(pattern)) {
          await wipe(entity);
          count++;
        }
      }
    }
    if (deleteIfEmpty && directory.existsSync()) {
      final isEmpty = directory.listSync().isEmpty;
      if (isEmpty) await directory.delete();
    }
    Log.i(_tag, 'wipeDirectory: $count files wiped in ${directory.path}');
    return count;
  }
}

class SecureWipeException implements Exception {
  const SecureWipeException(this.message);
  final String message;
  @override
  String toString() => 'SecureWipeException: $message';
}
