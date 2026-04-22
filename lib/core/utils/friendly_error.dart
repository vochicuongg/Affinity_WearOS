// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — friendly_error.dart
//  Maps raw Firebase/network exceptions into short, human-friendly messages
//  suitable for the tiny Wear OS screen (max ~3–4 words ideal).
// ═══════════════════════════════════════════════════════════════════════════

/// Converts a raw error string (e.g. from Firebase) into a short,
/// human-readable message for the Wear OS UI.
String friendlyError(Object error) {
  final msg = error.toString().toLowerCase();

  // ── Network / DNS ───────────────────────────────────────────────────────
  if (msg.contains('unavailable') ||
      msg.contains('unable to resolve host') ||
      msg.contains('unknownhostexception') ||
      msg.contains('no address associated')) {
    return 'No internet connection.\nCheck WiFi on your watch.';
  }

  if (msg.contains('network-request-failed') ||
      msg.contains('network error') ||
      msg.contains('etimedout') ||
      msg.contains('connection timed out')) {
    return 'Connection timed out.\nPlease try again.';
  }

  if (msg.contains('timeout') || msg.contains('future not completed')) {
    return 'Server not responding.\nPlease try again.';
  }

  // ── Firebase Auth ──────────────────────────────────────────────────────
  if (msg.contains('admin-restricted-operation')) {
    return 'Sign-in not enabled.\nContact support.';
  }

  if (msg.contains('too-many-requests')) {
    return 'Too many attempts.\nWait a moment.';
  }

  if (msg.contains('user-disabled')) {
    return 'Account disabled.\nContact support.';
  }

  // ── Firestore / Cloud ──────────────────────────────────────────────────
  if (msg.contains('permission-denied') || msg.contains('missing or insufficient')) {
    return 'Access denied.\nCheck Firestore rules.';
  }

  if (msg.contains('not-found') || msg.contains('invalid pair code')) {
    return 'Code not found.\nAsk your partner for a new code.';
  }

  if (msg.contains('already paired')) {
    return 'Already paired.\nUnpair first.';
  }

  if (msg.contains('expired')) {
    return 'Code expired.\nGenerate a new one.';
  }

  if (msg.contains('already been used')) {
    return 'Code already used.\nGenerate a new one.';
  }

  // ── Fallback ───────────────────────────────────────────────────────────
  // Keep it short for the watch screen.
  return 'Something went wrong.\nPlease try again.';
}
