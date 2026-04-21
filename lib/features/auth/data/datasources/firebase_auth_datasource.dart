// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — firebase_auth_datasource.dart
//  Implements silent Google Sign-In for Wear OS standalone devices.
//
//  Sign-in strategy (in order of preference):
//   1. GoogleSignIn().signInSilently() — works if the watch has a Google
//      account linked (Galaxy Watch FE always does after setup).
//   2. Firebase Anonymous auth — fallback that still gives a stable uid
//      for FCM/Firestore operations if Google sign-in is unavailable.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/utils/logger.dart';
import '../models/auth_user_model.dart';

abstract interface class IAuthRemoteDataSource {
  Stream<AuthUserModel> get authStateChanges;
  AuthUserModel get currentUser;
  Future<AuthUserModel> signInSilently();
  Future<void> signOut();
}

class FirebaseAuthDataSource implements IAuthRemoteDataSource {
  FirebaseAuthDataSource({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              // Scopes: email only — no extra permissions needed on watch.
              scopes: ['email'],
            );

  static const _tag = 'FirebaseAuthDataSource';

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  @override
  Stream<AuthUserModel> get authStateChanges =>
      _auth.authStateChanges().map((user) => AuthUserModel.fromFirebase(user));

  @override
  AuthUserModel get currentUser =>
      AuthUserModel.fromFirebase(_auth.currentUser);

  @override
  Future<AuthUserModel> signInSilently() async {
    // ── Strategy 1: Silent Google Sign-In ──────────────────────────────
    try {
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser != null) {
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final userCredential = await _auth.signInWithCredential(credential);
        Log.i(_tag, 'Google silent sign-in OK: ${userCredential.user?.uid}');
        return AuthUserModel.fromFirebase(userCredential.user);
      }
    } catch (e, st) {
      Log.w(_tag, 'Google silent sign-in unavailable, trying anonymous', error: e, stack: st);
    }

    // ── Strategy 2: Anonymous auth fallback ───────────────────────────
    // If user already has an anonymous session, reuse it.
    if (_auth.currentUser != null) {
      Log.i(_tag, 'Reusing existing session: ${_auth.currentUser!.uid}');
      return AuthUserModel.fromFirebase(_auth.currentUser);
    }
    final anonCredential = await _auth.signInAnonymously();
    Log.i(_tag, 'Anonymous sign-in OK: ${anonCredential.user?.uid}');
    return AuthUserModel.fromFirebase(anonCredential.user);
  }

  @override
  Future<void> signOut() async {
    await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
    Log.i(_tag, 'Signed out');
  }
}
