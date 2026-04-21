// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — main.dart  (Phase 3 update)
//  Added: FCM background handler registration + notification permissions.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/messaging/fcm_handler.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — Wear OS round faces are always portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Immersive mode: maximise screen real estate on 40–45 mm watch.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // ── Firebase Initialization ────────────────────────────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── FCM: register background handler BEFORE runApp ────────────────────
  // The background handler must be registered before Flutter engine is ready.
  registerFcmHandlers();

  // ── FCM: request notification + vibration permissions ─────────────────
  await requestFcmPermissions();

  runApp(const ProviderScope(child: WearApp()));
}
