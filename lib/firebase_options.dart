// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — firebase_options.dart
//  Generated from google-services.json for project: affinity-0411
//  Package: com.affinity.wear
//  DO NOT commit this file to public source control (contains API key).
// ═══════════════════════════════════════════════════════════════════════════

// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

abstract class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for Android (Wear OS). '
          'Platform: $defaultTargetPlatform',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyCVqd0PFn2HNbyrvQuA9229S1V_8tcj0E4',
    appId:             '1:695709413805:android:09b1709719a7bd318d7124',
    messagingSenderId: '695709413805',
    projectId:         'affinity-0411',
    storageBucket:     'affinity-0411.firebasestorage.app',
  );
}
