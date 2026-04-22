// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — main.dart  (Phase 3 update)
//  Added: FCM background handler registration + notification permissions.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/messaging/fcm_handler.dart';
import 'core/utils/logger.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — Wear OS round faces are always portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Immersive mode: maximise screen real estate on 40–45 mm watch.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // ── Firebase Initialization ────────────────────────────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Firestore: enable offline persistence & set cache ──────────────────
  // This ensures writes land in local cache even if the network is down.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  Log.i('main', 'Firestore offline persistence enabled');

  // ── FCM: register background handler BEFORE runApp ────────────────────
  // The background handler must be registered before Flutter engine is ready.
  registerFcmHandlers();

  // ── FCM: request notification + vibration permissions ─────────────────
  await requestFcmPermissions();

  runApp(const ProviderScope(child: WearApp()));
}
