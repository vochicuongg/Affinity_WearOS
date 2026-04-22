// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — auth_provider.dart
//  Riverpod providers for authentication state.
//
//  Usage in widgets:
//    final user = ref.watch(authUserProvider);
//    final authState = ref.watch(authStateProvider);
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/encryption_service.dart';
import '../../../../core/security/key_storage_service.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/firebase_auth_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/auth_user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../domain/usecases/silent_sign_in_use_case.dart';

// ── Infrastructure Providers ──────────────────────────────────────────────

final keyStorageProvider = Provider<KeyStorageService>(
  (_) => KeyStorageService(),
);

final encryptionServiceProvider = Provider<IEncryptionService>((ref) {
  return EncryptionService(ref.read(keyStorageProvider));
});

final authDataSourceProvider = Provider<IAuthRemoteDataSource>(
  (_) => FirebaseAuthDataSource(),
);

final authRepositoryProvider = Provider<IAuthRepository>((ref) {
  return AuthRepositoryImpl(ref.read(authDataSourceProvider));
});

final silentSignInUseCaseProvider = Provider<SilentSignInUseCase>((ref) {
  return SilentSignInUseCase(ref.read(authRepositoryProvider));
});

// ── Auth State Stream Provider ────────────────────────────────────────────

/// Streams the current [AuthUser]; emits [AuthUser.empty] when signed out.
final authUserProvider = StreamProvider<AuthUser>((ref) {
  return ref.read(authRepositoryProvider).authStateChanges;
});

// ── Auth Notifier: handles sign-in sequence ───────────────────────────────

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user = AuthUser.empty,
    this.errorMessage,
  });

  final AuthStatus status;
  final AuthUser user;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthNotifier extends Notifier<AuthState> {
  static const _tag = 'AuthNotifier';

  @override
  AuthState build() {
    // Kick off silent sign-in as soon as the provider is first read.
    _initAuth();
    return const AuthState(status: AuthStatus.loading);
  }

  Future<void> _initAuth() async {
    try {
      final result = await ref
          .read(silentSignInUseCaseProvider)
          .call()
          .timeout(const Duration(seconds: 15));
      result.fold(
        (failure) {
          Log.e(_tag, 'Auth failed: ${failure.message}');
          state = AuthState(
            status: AuthStatus.unauthenticated,
            errorMessage: friendlyError(failure.message),
          );
        },
        (user) async {
          Log.i(_tag, 'Authenticated: ${user.uid}');
          state = AuthState(status: AuthStatus.authenticated, user: user);
          // After auth: ensure RSA key pair exists.
          await _ensureKeyPairExists();
        },
      );
    } catch (e) {
      // Timeout or unexpected error — go to unauthenticated so user can retry.
      Log.e(_tag, 'Auth timed out: $e');
      state = AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: friendlyError(e),
      );
    }
  }

  Future<void> _ensureKeyPairExists() async {
    final encryption = ref.read(encryptionServiceProvider);
    final keyStorage = ref.read(keyStorageProvider);

    // Only generate keys if none exist.
    if (await keyStorage.loadPublicKey() == null) {
      final result = await encryption.generateAndStoreKeyPair();
      result.fold(
        (f) => Log.e(_tag, 'Key gen failed: ${f.message}'),
        (_) => Log.i(_tag, 'RSA key pair ready'),
      );
    } else {
      Log.i(_tag, 'RSA key pair already exists');
    }
  }

  /// Public method to retry sign-in after failure (used by the retry button in app.dart).
  Future<void> retrySignIn() async {
    state = const AuthState(status: AuthStatus.loading);
    await _initAuth();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
