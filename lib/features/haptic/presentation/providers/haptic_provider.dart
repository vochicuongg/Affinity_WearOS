// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — haptic_provider.dart
//  Riverpod wiring for the entire Haptic Morse Code feature.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/haptic/haptic_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pairing/domain/entities/pair_session.dart';
import '../../../pairing/presentation/providers/pairing_provider.dart';
import '../../data/datasources/haptic_local_datasource.dart';
import '../../data/datasources/haptic_remote_datasource.dart';
import '../../data/repositories/haptic_repository_impl.dart';
import '../../domain/entities/haptic_signal.dart';
import '../../domain/repositories/i_haptic_repository.dart';
import '../../domain/usecases/haptic_use_cases.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final hapticServiceProvider = Provider<HapticService>(
  (_) => HapticService(),
);

final hapticLocalDSProvider = Provider<HapticLocalDataSource>((ref) {
  return HapticLocalDataSource(ref.read(hapticServiceProvider));
});

final hapticRemoteDSProvider = Provider<HapticRemoteDataSource>((ref) {
  return HapticRemoteDataSource(encryption: ref.read(encryptionServiceProvider));
});

final hapticRepositoryProvider = Provider<IHapticRepository>((ref) {
  return HapticRepositoryImpl(
    ref.read(hapticRemoteDSProvider),
    ref.read(hapticLocalDSProvider),
  );
});

// ── Use cases ─────────────────────────────────────────────────────────────

final sendHapticUseCaseProvider = Provider<SendHapticSignalUseCase>((ref) {
  return SendHapticSignalUseCase(ref.read(hapticRepositoryProvider));
});

final watchSignalsUseCaseProvider = Provider<WatchIncomingSignalsUseCase>((ref) {
  return WatchIncomingSignalsUseCase(ref.read(hapticRepositoryProvider));
});

// ── Incoming signal stream ────────────────────────────────────────────────

/// Auto-plays and marks as played each incoming haptic signal.
final incomingHapticProvider = StreamProvider<HapticSignal?>((ref) async* {
  final pairingState = ref.watch(pairingNotifierProvider);
  final session = pairingState.session;
  final authState = ref.watch(authNotifierProvider);

  if (session == null || !authState.isAuthenticated) {
    yield null;
    return;
  }

  final myUid = authState.user.uid;
  final repo   = ref.read(hapticRepositoryProvider);

  await for (final either in repo.watchIncomingSignals(myUid, session.coupleId)) {
    final signal = either.fold((_) => null, (s) => s);
    if (signal == null) continue;

    // Auto-play on receive
    Log.i('HapticProvider', 'Incoming: ${signal.signal.displayName}');
    await repo.playSignal(signal);
    await repo.markPlayed(signal.id, session.coupleId);
    yield signal;
  }
});

// ── Haptic Send State Machine ─────────────────────────────────────────────

enum HapticSendStatus { idle, sending, sent, error }

class HapticState {
  const HapticState({
    this.status = HapticSendStatus.idle,
    this.lastSent,
    this.errorMessage,
    this.isTapping = false,
    this.tapDurations = const [],
  });

  final HapticSendStatus status;
  final LoveSignal? lastSent;
  final String? errorMessage;
  final bool isTapping;                // user is in Morse tap-input mode
  final List<int> tapDurations;        // accumulated tap durations (ms)

  HapticState copyWith({
    HapticSendStatus? status,
    LoveSignal? lastSent,
    String? errorMessage,
    bool? isTapping,
    List<int>? tapDurations,
  }) =>
      HapticState(
        status:       status       ?? this.status,
        lastSent:     lastSent     ?? this.lastSent,
        errorMessage: errorMessage ?? this.errorMessage,
        isTapping:    isTapping    ?? this.isTapping,
        tapDurations: tapDurations ?? this.tapDurations,
      );
}

class HapticNotifier extends Notifier<HapticState> {
  static const _tag = 'HapticNotifier';

  @override
  HapticState build() => const HapticState();

  IHapticRepository get _repo => ref.read(hapticRepositoryProvider);

  // ── Send a predefined Love Signal ─────────────────────────────────────


  Future<void> sendSignal(LoveSignal signal) async {
    state = state.copyWith(status: HapticSendStatus.sending);

    final pairingState = ref.read(pairingNotifierProvider);
    final session = pairingState.session;
    final authState = ref.read(authNotifierProvider);

    if (session == null || !authState.isAuthenticated) {
      state = state.copyWith(
        status: HapticSendStatus.error,
        errorMessage: 'Not paired with a partner',
      );
      return;
    }

    final myUid    = authState.user.uid;
    final partner  = _partnerFrom(session, myUid);

    // Also play locally so the sender feels the heartbeat
    await _repo.playLocalSignal(signal);

    final result = await _repo.sendSignal(
      fromUid:    myUid,
      toUid:      partner.uid,
      toFcmToken: partner.fcmToken,
      coupleId:   session.coupleId,
      signal:     signal,
    );

    result.fold(
      (f) {
        Log.e(_tag, 'sendSignal failed: ${f.message}');
        state = state.copyWith(
          status: HapticSendStatus.error,
          errorMessage: f.message,
        );
      },
      (_) {
        Log.i(_tag, 'Signal sent: ${signal.displayName}');
        state = state.copyWith(
          status: HapticSendStatus.sent,
          lastSent: signal,
        );
        // Auto-reset to idle after 2 s
        Future.delayed(const Duration(seconds: 2), () {
          if (state.status == HapticSendStatus.sent) {
            state = const HapticState();
          }
        });
      },
    );
  }

  // ── Morse tap input ───────────────────────────────────────────────────

  void startTapMode() =>
      state = state.copyWith(isTapping: true, tapDurations: []);

  void recordTap(int durationMs) {
    state = state.copyWith(
      tapDurations: [...state.tapDurations, durationMs],
    );
  }

  /// Finalises tap sequence → sends as custom haptic signal.
  Future<void> finaliseTapMorse() async {
    if (state.tapDurations.isEmpty) {
      state = state.copyWith(isTapping: false);
      return;
    }

    final pairingState = ref.read(pairingNotifierProvider);
    final session = pairingState.session;
    final authState = ref.read(authNotifierProvider);

    if (session == null || !authState.isAuthenticated) return;
    final myUid   = authState.user.uid;
    final partner = _partnerFrom(session, myUid);

    // Build the vibration pattern from the tap durations
    final hapticSvc = ref.read(hapticServiceProvider);
    await hapticSvc.playTapSequence(state.tapDurations);

    // Derive the pattern from tap durations for encoding in the signal
    final pattern = state.tapDurations
        .expand((d) => [d, 120])
        .toList()
      ..removeLast();

    state = state.copyWith(isTapping: false, status: HapticSendStatus.sending);

    final result = await _repo.sendSignal(
      fromUid:       myUid,
      toUid:         partner.uid,
      toFcmToken:    partner.fcmToken,
      coupleId:      session.coupleId,
      signal:        LoveSignal.custom,
      customPattern: pattern,
    );

    result.fold(
      (f) => state = state.copyWith(
        status: HapticSendStatus.error,
        errorMessage: f.message,
      ),
      (_) => state = state.copyWith(status: HapticSendStatus.sent),
    );
  }

  void reset() => state = const HapticState();

  // ── Private helper ────────────────────────────────────────────────────

  ({String uid, String fcmToken}) _partnerFrom(PairSession session, String myUid) =>
      (
        uid:      myUid == session.user1Uid ? session.user2Uid : session.user1Uid,
        fcmToken: session.partnerFcmToken(myUid),
      );
}

final hapticNotifierProvider = NotifierProvider<HapticNotifier, HapticState>(
  HapticNotifier.new,
);
