// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pairing_provider.dart
//  Riverpod state management for the full pairing flow.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/encryption_service.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/firestore_pairing_datasource.dart';
import '../../data/repositories/pairing_repository_impl.dart';
import '../../domain/entities/pair_session.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/i_pairing_repository.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final pairingDataSourceProvider = Provider<FirestorePairingDataSource>(
  (_) => FirestorePairingDataSource(),
);

final pairingRepositoryProvider = Provider<IPairingRepository>((ref) {
  return PairingRepositoryImpl(ref.read(pairingDataSourceProvider));
});

// ── Streams ───────────────────────────────────────────────────────────────

/// Watches this device's Firestore user profile in real time.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  if (!authState.isAuthenticated) return const Stream.empty();
  return ref
      .read(pairingRepositoryProvider)
      .watchUserProfile(authState.user.uid)
      .map((either) => either.fold((_) => null, (p) => p));
});

/// Convenience: true when there is an active pair session loaded in memory.
final isPairedProvider = Provider<bool>((ref) {
  final pairingState = ref.watch(pairingNotifierProvider);
  return pairingState.session != null;
});

// ── Pairing State Machine ─────────────────────────────────────────────────

enum PairingStatus {
  idle,
  initializingProfile,
  generatingCode,
  awaitingPartner,
  enteringCode,
  verifying,
  paired,
  error,
}

class PairingState {
  const PairingState({
    this.status = PairingStatus.idle,
    this.pairCode,
    this.session,
    this.errorMessage,
    this.enteredCode = '',
  });

  final PairingStatus status;
  final String? pairCode;           // Code shown to the initiator
  final PairSession? session;
  final String? errorMessage;
  final String enteredCode;         // Code being typed by the joiner

  PairingState copyWith({
    PairingStatus? status,
    String? pairCode,
    PairSession? session,
    String? errorMessage,
    String? enteredCode,
  }) =>
      PairingState(
        status: status ?? this.status,
        pairCode: pairCode ?? this.pairCode,
        session: session ?? this.session,
        errorMessage: errorMessage ?? this.errorMessage,
        enteredCode: enteredCode ?? this.enteredCode,
      );
}

class PairingNotifier extends Notifier<PairingState> {
  static const _tag = 'PairingNotifier';

  @override
  PairingState build() {
    // Use ref.listen (not ref.watch) so build() is NOT re-invoked on
    // profile changes — only the callback fires, preserving state.
    ref.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, next) {
      next.whenData((profile) => _onProfileChanged(profile));
    });

    // Also check the current profile value immediately (covers app restart
    // when the profile is already loaded before this notifier is built).
    Future.microtask(() {
      final currentProfile = ref.read(userProfileProvider).value;
      _onProfileChanged(currentProfile);
    });

    return const PairingState();
  }

  void _onProfileChanged(UserProfile? profile) {
    if (profile == null) return;
    if (profile.isPaired && state.session == null) {
      Log.i(_tag, 'Profile paired, restoring session...');
      _restoreSession();
    } else if (!profile.isPaired && state.session != null) {
      Log.i(_tag, 'Profile unpaired, resetting state.');
      state = const PairingState();
    }
  }

  IPairingRepository get _repo => ref.read(pairingRepositoryProvider);
  IEncryptionService get _crypto => ref.read(encryptionServiceProvider);
  String get _uid => ref.read(authNotifierProvider).user.uid;

  // ── Step 1: Register this device in Firestore ─────────────────────────
  //   Non-blocking: if Firestore is unreachable (DNS fail, no network)
  //   the profile write times out and the UI proceeds to idle.

  Future<void> initializeProfile() async {
    state = state.copyWith(status: PairingStatus.initializingProfile);
    try {
      final pubKeyResult = await _crypto.getLocalPublicKey();
      final publicKeyJson = pubKeyResult.getOrElse(() => '');

      final fcmToken = await FirestorePairingDataSource().getFcmToken()
          .timeout(const Duration(seconds: 5), onTimeout: () => null) ?? '';

      final profile = UserProfile(
        uid:          _uid,
        fcmToken:     fcmToken,
        publicKeyJson: publicKeyJson,
        createdAt:    DateTime.now(),
      );

      final result = await _repo.initializeUserProfile(profile)
          .timeout(const Duration(seconds: 10));
      result.fold(
        (f) {
          Log.w(_tag, 'Profile init failed (continuing): ${f.message}');
          // Proceed to idle — the user can still generate/enter codes.
          state = state.copyWith(status: PairingStatus.idle);
        },
        (_) async {
          Log.i(_tag, 'Profile initialized');
          // Phase 2 Fix: Attempt to restore active pair session on app startup
          await _restoreSession();
        },
      );
    } catch (e) {
      // Timeout or network error — proceed to idle anyway.
      Log.w(_tag, 'Profile init timed out (continuing): $e');
      state = state.copyWith(status: PairingStatus.idle);
    }
  }

  Future<void> _restoreSession() async {
    final sessionResult = await _repo.getActivePairSession(_uid);
    await sessionResult.fold(
      (_) async => state = state.copyWith(status: PairingStatus.idle),
      (session) async {
        if (session != null) {
          Log.i(_tag, 'Restored active session: ${session.coupleId}');
          await _crypto.deriveSessionKey(session.partnerPublicKeyJson(_uid));
          state = state.copyWith(
            status: PairingStatus.paired,
            session: session,
          );
        } else {
          state = state.copyWith(status: PairingStatus.idle);
        }
      },
    );
  }

  // ── Step 2a: Initiator generates a pair code ──────────────────────────

  Future<void> generateCode() async {
    state = state.copyWith(status: PairingStatus.generatingCode);

    try {
      final pubKeyResult = await _crypto.getLocalPublicKey();
      final publicKeyJson = pubKeyResult.getOrElse(() => '');
      final fcmToken = await FirestorePairingDataSource().getFcmToken()
          .timeout(const Duration(seconds: 5), onTimeout: () => null) ?? '';

      final result = await _repo.generatePairCode(
        initiatorUid:           _uid,
        initiatorFcmToken:      fcmToken,
        initiatorPublicKeyJson: publicKeyJson,
      ).timeout(const Duration(seconds: 10));

      result.fold(
        (f) => state = state.copyWith(
          status: PairingStatus.error,
          errorMessage: friendlyError(f.message),
        ),
        (code) => state = state.copyWith(
          status: PairingStatus.awaitingPartner,
          pairCode: code,
        ),
      );
    } catch (e) {
      Log.e(_tag, 'generateCode failed: $e');
      state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: friendlyError(e),
      );
    }
  }

  // ── Step 2b: Joiner appends a digit to the code entry ────────────────

  void appendDigit(String digit) {
    if (state.enteredCode.length >= 6) return;
    state = state.copyWith(enteredCode: state.enteredCode + digit);
    if (state.enteredCode.length == 6) acceptCode();
  }

  void deleteDigit() {
    if (state.enteredCode.isEmpty) return;
    state = state.copyWith(
      enteredCode: state.enteredCode.substring(0, state.enteredCode.length - 1),
    );
  }

  void switchToEnterCode() =>
      state = state.copyWith(status: PairingStatus.enteringCode, enteredCode: '');

  // ── Step 3: Joiner accepts the code ───────────────────────────────────

  Future<void> acceptCode() async {
    state = state.copyWith(status: PairingStatus.verifying);

    try {
      final pubKeyResult = await _crypto.getLocalPublicKey();
      final publicKeyJson = pubKeyResult.getOrElse(() => '');
      final fcmToken = await FirestorePairingDataSource().getFcmToken()
          .timeout(const Duration(seconds: 5), onTimeout: () => null) ?? '';

      final result = await _repo.acceptPairCode(
        code:                state.enteredCode,
        joinerUid:           _uid,
        joinerFcmToken:      fcmToken,
        joinerPublicKeyJson: publicKeyJson,
      ).timeout(const Duration(seconds: 10));

      await result.fold(
        (f) async {
          Log.e(_tag, 'acceptPairCode error: ${f.message}');
          state = state.copyWith(
            status: PairingStatus.error,
            errorMessage: friendlyError(f.message),
            enteredCode: '',
          );
        },
        (session) async {
          Log.i(_tag, 'Paired! coupleId=${session.coupleId}');
          // Derive shared session key using partner's public key.
          await _crypto.deriveSessionKey(session.partnerPublicKeyJson(_uid));
          state = state.copyWith(
            status: PairingStatus.paired,
            session: session,
          );
        },
      );
    } catch (e) {
      Log.e(_tag, 'acceptCode failed: $e');
      state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: friendlyError(e),
        enteredCode: '',
      );
    }
  }

  Future<void> unpair() async {
    final currentSession = state.session;
    if (currentSession == null) return;

    state = state.copyWith(status: PairingStatus.idle);
    
    final result = await _repo.unpair(currentSession);
    result.fold(
      (f) => Log.e(_tag, 'Unpair failed: ${f.message}'),
      (_) {
        Log.i(_tag, 'Successfully unpaired');
        state = const PairingState();
      },
    );
  }

  void reset() => state = const PairingState();
}

final pairingNotifierProvider = NotifierProvider<PairingNotifier, PairingState>(
  PairingNotifier.new,
);
