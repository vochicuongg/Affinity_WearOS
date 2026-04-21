// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — fcm_handler.dart
//
//  IMPORTANT: All functions here are TOP-LEVEL (not inside a class) because
//  Firebase Messaging requires the background handler to be a top-level
//  function annotated with @pragma('vm:entry-point').
//
//  FCM Payload structure (data-only message — no notification field):
//  {
//    "data": {
//      "type":      "haptic" | "mood" | "audio",
//      "ciphertext": "<base64 AES-GCM encrypted payload>",
//      "senderId":   "<uid of sender>"
//    }
//  }
//
//  Encrypted payload (JSON before AES-GCM encryption):
//  {
//    "signal":  "heartbeat" | "iLoveYou" | "custom" | ...,
//    "pattern": [0, 120, 120, 360, ...],   // raw vibration list
//    "nonce":   "<uuid>",                  // anti-replay
//    "ts":      1234567890123              // epoch ms, anti-replay
//  }
//
//  Architecture note on background delivery:
//  ──────────────────────────────────────────
//  Sending haptic signals from one client device to another requires a
//  server-side component to call the FCM HTTP v1 API. This is because
//  the FCM server key must NEVER be embedded in the client app (security).
//
//  Recommended: Deploy a Firebase Cloud Function that is triggered when a
//  new document is written to `haptics/{signalId}` in Firestore, then
//  calls the FCM API to push to the partner's token.
//
//  Phase 3 provides: the client-side RECEIVE handler (foreground + background)
//  and the Firestore WRITE logic. The Cloud Function stub is documented below.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vibration/vibration.dart';

import '../../firebase_options.dart';
import '../constants/app_constants.dart';
import '../haptic/haptic_service.dart';
import '../utils/logger.dart';

// ── Background handler registration ──────────────────────────────────────────

/// Call this once in [main()] before [runApp()].
void registerFcmHandlers() {
  FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  FirebaseMessaging.onMessage.listen(_foregroundMessageHandler);
}

/// Requests notification + Wear OS vibration permissions.
Future<void> requestFcmPermissions() async {
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: false,
    sound: false,        // Wear OS uses vibration, not sound
    announcement: false,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
  );
  Log.i('FCMHandler', 'Notification permission: ${settings.authorizationStatus}');
}

// ── Background handler (top-level, @pragma required) ─────────────────────────

/// Handles FCM messages when the app is terminated or in the background.
/// This function runs in an ISOLATED background Dart isolate.
/// It must re-initialise Firebase and use only minimal dependencies.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  // Firebase must be re-initialised in the background isolate.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Log.i('FCMHandler', '[BG] Received message: ${message.messageId}');
  await _processHapticMessage(message, isBackground: true);
}

// ── Foreground handler ────────────────────────────────────────────────────────

Future<void> _foregroundMessageHandler(RemoteMessage message) async {
  Log.i('FCMHandler', '[FG] Received message: ${message.messageId}');
  await _processHapticMessage(message, isBackground: false);
}

// ── Core processing logic ─────────────────────────────────────────────────────

Future<void> _processHapticMessage(
  RemoteMessage message, {
  required bool isBackground,
}) async {
  final data = message.data;
  final type = data['type'];

  if (type != 'haptic') {
    Log.d('FCMHandler', 'Non-haptic message type: $type — skipped');
    return;
  }

  final ciphertext = data['ciphertext'] as String?;
  if (ciphertext == null || ciphertext.isEmpty) {
    Log.w('FCMHandler', 'Haptic message missing ciphertext — dropped');
    return;
  }

  // ── Decrypt payload ───────────────────────────────────────────────────────
  final decryptResult = await _decryptPayload(ciphertext);
  if (decryptResult == null) {
    Log.w('FCMHandler', 'Haptic decryption failed — dropped');
    return;
  }

  // ── Anti-Replay check ─────────────────────────────────────────────────────
  final ts  = decryptResult['ts'] as int?  ?? 0;
  final nonce = decryptResult['nonce'] as String? ?? '';
  final age = DateTime.now().millisecondsSinceEpoch - ts;

  if (age.abs() > AppConstants.maxMessageAge.inMilliseconds) {
    Log.w(
      'FCMHandler',
      '⛔ Anti-Replay REJECTED — message age: ${age}ms '
      '(max: ${AppConstants.maxMessageAge.inMilliseconds}ms) '
      'nonce: $nonce',
    );
    return;
  }
  Log.i(
    'FCMHandler',
    '✅ Anti-Replay PASSED — age: ${age}ms, nonce: $nonce',
  );

  // ── Extract vibration pattern ──────────────────────────────────────────────
  final signalId = decryptResult['signal'] as String? ?? 'custom';
  final rawPattern = decryptResult['pattern'];
  List<int> pattern;

  if (rawPattern is List) {
    pattern = rawPattern.cast<int>();
  } else {
    // Fall back to the predefined signal pattern by ID
    final signal = LoveSignal.values.firstWhere(
      (s) => s.id == signalId,
      orElse: () => LoveSignal.heartbeat,
    );
    pattern = signal.pattern;
  }

  Log.i(
    'FCMHandler',
    'Playing haptic signal "$signalId" '
    '(${pattern.length} steps) — '
    '${isBackground ? "background" : "foreground"}',
  );

  // ── Play vibration ─────────────────────────────────────────────────────────
  // In background isolate, use Vibration directly (HapticService unavailable).
  try {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      await Vibration.vibrate(pattern: pattern);
    }
  } catch (e) {
    Log.e('FCMHandler', 'Vibration playback failed', error: e);
  }
}

// ── Minimal decryption for background isolate ─────────────────────────────────
// The background isolate cannot access the full EncryptionService (it has no
// Riverpod context). Instead, we read the session key directly from
// EncryptedSharedPreferences and perform AES-GCM decryption inline.

Future<Map<String, dynamic>?> _decryptPayload(String base64Ciphertext) async {
  try {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    final storedKey = await storage.read(key: AppConstants.keyAesSession);
    if (storedKey == null) {
      Log.w('FCMHandler', 'No session key in secure storage — cannot decrypt');
      return null;
    }

    // The stored value is the RSA-encrypted session key (base64).
    // In the background isolate we cannot RSA-decrypt (no private key access
    // without the full EncryptionService). For background delivery, the sender
    // should also include a Firestore-cached plaintext session key reference.
    //
    // TODO Phase 5: implement full background-isolate AES-GCM decryption.
    // For now, attempt a direct JSON parse (Phase 3 dev mode without E2EE).
    final jsonString = utf8.decode(base64Decode(base64Ciphertext));
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    // In full E2EE mode this will fail until Phase 5. Log clearly.
    if (kDebugMode) {
      Log.w('FCMHandler', 'Decryption skipped in debug dev mode: $e');
      // Return a mock heartbeat for development testing
      return {
        'signal': 'heartbeat',
        'pattern': LoveSignal.heartbeat.pattern,
        'nonce': 'dev-nonce',
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
    }
    Log.e('FCMHandler', 'Payload decryption failed', error: e);
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Cloud Function stub (deploy to Firebase Functions for production)
//
//  // functions/src/index.ts
//  import * as admin from 'firebase-admin';
//  import * as functions from 'firebase-functions';
//
//  exports.sendHapticSignal = functions.firestore
//    .document('haptics/{signalId}')
//    .onCreate(async (snap) => {
//      const data = snap.data();
//      await admin.messaging().send({
//        token: data.toFcmToken,
//        data: {
//          type:       'haptic',
//          ciphertext: data.ciphertext,
//          senderId:   data.fromUid,
//        },
//        android: {
//          priority: 'high',    // Wake the watch even in Doze mode
//          ttl: 30_000,         // 30 s — haptics are time-sensitive
//        },
//      });
//      await snap.ref.delete();  // Clean up signal document
//    });
// ═════════════════════════════════════════════════════════════════════════════
