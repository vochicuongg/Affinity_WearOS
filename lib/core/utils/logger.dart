// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — logger.dart
//  Structured, level-filtered logger using the `logger` package.
//  In release builds all logging is stripped to avoid leaking sensitive data.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Global logger instance. Use the static getters for typed logging.
///
/// Usage:
///   Log.d('EncryptionService', 'Key generated in ${elapsed}ms');
///   Log.e('PairingRepo', 'Firestore write failed', error: e, stack: st);
abstract final class Log {
  static final Logger _logger = Logger(
    // In release mode: suppress everything to prevent data leakage.
    // In debug mode: pretty-print with colours and source location.
    level: kReleaseMode ? Level.off : Level.trace,
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 8,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    // Structured output filter: suppress verbose logs in profile mode.
    filter: kProfileMode ? _ProfileFilter() : null,
  );

  // ── Convenience wrappers ──────────────────────────────────────────────

  /// Verbose trace — only shown in debug mode.
  static void t(String tag, String msg) =>
      _logger.t('[$tag] $msg');

  /// Debug information.
  static void d(String tag, String msg) =>
      _logger.d('[$tag] $msg');

  /// Informational milestone (pairing established, Firebase ready, etc.).
  static void i(String tag, String msg) =>
      _logger.i('[$tag] $msg');

  /// Warning — something unexpected but recoverable.
  static void w(String tag, String msg, {Object? error, StackTrace? stack}) =>
      _logger.w('[$tag] $msg', error: error, stackTrace: stack);

  /// Error — operation failed; [error] and [stack] are captured.
  static void e(String tag, String msg, {Object? error, StackTrace? stack}) =>
      _logger.e('[$tag] $msg', error: error, stackTrace: stack);

  /// Fatal — unrecoverable error (crash-level).
  static void f(String tag, String msg, {Object? error, StackTrace? stack}) =>
      _logger.f('[$tag] $msg', error: error, stackTrace: stack);
}

/// Suppresses debug/trace logs in Flutter profile mode.
class _ProfileFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) => event.level.index >= Level.info.index;
}
