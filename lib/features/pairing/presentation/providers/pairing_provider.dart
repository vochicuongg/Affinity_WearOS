// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pairing_provider.dart
//  Riverpod state management for the full pairing flow.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/security/encryption_service.dart';
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

/// Convenience: true when the user profile shows a paired partner.
final isPairedProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(userProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.isPaired ?? false,
    orElse: () => false,
  );
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
  PairingState build() => const PairingState();

  IPairingRepository get _repo => ref.read(pairingRepositoryProvider);
  IEncryptionService get _crypto => ref.read(encryptionServiceProvider);
  String get _uid => ref.read(authNotifierProvider).user.uid;

  // ── Step 1: Register this device in Firestore ─────────────────────────

  Future<void> initializeProfile() async {
    state = state.copyWith(status: PairingStatus.initializingProfile);
    final pubKeyResult = await _crypto.getLocalPublicKey();
    final publicKeyJson = pubKeyResult.getOrElse(() => '');

    final fcmToken = await FirestorePairingDataSource().getFcmToken() ?? '';

    final profile = UserProfile(
      uid:          _uid,
      fcmToken:     fcmToken,
      publicKeyJson: publicKeyJson,
      createdAt:    DateTime.now(),
    );

    final result = await _repo.initializeUserProfile(profile);
    result.fold(
      (f) {
        Log.e(_tag, 'Profile init failed: ${f.message}');
        state = state.copyWith(
          status: PairingStatus.error,
          errorMessage: f.message,
        );
      },
      (_) {
        Log.i(_tag, 'Profile initialized');
        state = state.copyWith(status: PairingStatus.idle);
      },
    );
  }

  // ── Step 2a: Initiator generates a pair code ──────────────────────────

  Future<void> generateCode() async {
    state = state.copyWith(status: PairingStatus.generatingCode);

    final pubKeyResult = await _crypto.getLocalPublicKey();
    final publicKeyJson = pubKeyResult.getOrElse(() => '');
    final fcmToken = await FirestorePairingDataSource().getFcmToken() ?? '';

    final result = await _repo.generatePairCode(
      initiatorUid:           _uid,
      initiatorFcmToken:      fcmToken,
      initiatorPublicKeyJson: publicKeyJson,
    );

    result.fold(
      (f) => state = state.copyWith(
        status: PairingStatus.error,
        errorMessage: f.message,
      ),
      (code) => state = state.copyWith(
        status: PairingStatus.awaitingPartner,
        pairCode: code,
      ),
    );
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

    final pubKeyResult = await _crypto.getLocalPublicKey();
    final publicKeyJson = pubKeyResult.getOrElse(() => '');
    final fcmToken = await FirestorePairingDataSource().getFcmToken() ?? '';

    final result = await _repo.acceptPairCode(
      code:                state.enteredCode,
      joinerUid:           _uid,
      joinerFcmToken:      fcmToken,
      joinerPublicKeyJson: publicKeyJson,
    );

    await result.fold(
      (f) async {
        Log.e(_tag, 'acceptPairCode error: ${f.message}');
        state = state.copyWith(
          status: PairingStatus.error,
          errorMessage: f.message,
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
  }

  void reset() => state = const PairingState();
}

final pairingNotifierProvider = NotifierProvider<PairingNotifier, PairingState>(
  PairingNotifier.new,
);
