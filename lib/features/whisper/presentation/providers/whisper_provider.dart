// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_provider.dart
//  WhisperNotifier: manages the full PTT state machine.
//
//  States:
//    idle          → user not in PTT mode
//    recording     → hold-to-talk in progress
//    sending       → upload + encrypt in flight
//    delivered     → waiting for partner to play
//    receivedNew   → incoming whisper awaiting play
//    playing       → playback in progress
//    wiped         → both local + remote files deleted
//    error         → any step failed
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/audio_service.dart';
import '../../../../core/audio/secure_wipe_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pairing/presentation/providers/pairing_provider.dart';
import '../../data/datasources/whisper_local_datasource.dart';
import '../../data/datasources/whisper_remote_datasource.dart';
import '../../data/repositories/whisper_repository_impl.dart';
import '../../domain/entities/whisper_message.dart';
import '../../domain/repositories/i_whisper_repository.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final audioServiceProvider = Provider<AudioService>((_) => AudioService());

final secureWipeServiceProvider = Provider<SecureWipeService>(
  (_) => SecureWipeService(),
);

final whisperLocalDSProvider = Provider<WhisperLocalDataSource>((ref) =>
    WhisperLocalDataSource(
      encryption:   ref.read(encryptionServiceProvider),
      audioService: ref.read(audioServiceProvider),
      wipeService:  ref.read(secureWipeServiceProvider),
    ));

final whisperRemoteDSProvider = Provider<WhisperRemoteDataSource>(
  (_) => WhisperRemoteDataSource(),
);

final whisperRepositoryProvider = Provider<IWhisperRepository>((ref) =>
    WhisperRepositoryImpl(
      ref.read(whisperLocalDSProvider),
      ref.read(whisperRemoteDSProvider),
    ));

// ── State ─────────────────────────────────────────────────────────────────

enum WhisperUiStatus {
  idle,
  recording,
  sending,
  delivered,
  receivedNew,
  downloading,
  playing,
  wiped,
  error,
}

class WhisperUiState {
  const WhisperUiState({
    this.status = WhisperUiStatus.idle,
    this.message,
    this.amplitudes = const [],
    this.recordSeconds = 0,
    this.errorMessage,
    this.incomingQueue = const [],
  });

  final WhisperUiStatus status;
  final WhisperMessage? message;
  final List<double> amplitudes;       // real-time for waveform
  final int recordSeconds;
  final String? errorMessage;
  final List<WhisperMessage> incomingQueue; // unplayed incoming whispers

  bool get isRecording  => status == WhisperUiStatus.recording;
  bool get hasPending   => incomingQueue.isNotEmpty;

  WhisperUiState copyWith({
    WhisperUiStatus? status,
    WhisperMessage? message,
    List<double>? amplitudes,
    int? recordSeconds,
    String? errorMessage,
    List<WhisperMessage>? incomingQueue,
  }) =>
      WhisperUiState(
        status:        status        ?? this.status,
        message:       message       ?? this.message,
        amplitudes:    amplitudes    ?? this.amplitudes,
        recordSeconds: recordSeconds ?? this.recordSeconds,
        errorMessage:  errorMessage  ?? this.errorMessage,
        incomingQueue: incomingQueue ?? this.incomingQueue,
      );
}

// ── WhisperNotifier ───────────────────────────────────────────────────────

class WhisperNotifier extends Notifier<WhisperUiState> {
  static const _tag = 'WhisperNotifier';

  Timer? _recordTimer;
  StreamSubscription<double>? _ampSub;
  StreamSubscription<dynamic>? _incomingSub;
  String? _currentRecordPath;

  @override
  WhisperUiState build() {
    ref.onDispose(_cleanup);
    _startIncomingListener();
    return const WhisperUiState();
  }

  IWhisperRepository get _repo => ref.read(whisperRepositoryProvider);
  WhisperLocalDataSource get _local => ref.read(whisperLocalDSProvider);

  // ── PTT: Hold to talk ─────────────────────────────────────────────────────

  Future<void> onPttPressStart() async {
    if (state.status == WhisperUiStatus.recording) return;

    state = state.copyWith(
      status:       WhisperUiStatus.recording,
      amplitudes:   [],
      recordSeconds: 0,
    );

    final pairingState = ref.read(pairingNotifierProvider);
    final session      = pairingState.session;
    final authState    = ref.read(authNotifierProvider);
    if (session == null || !authState.isAuthenticated) {
      state = state.copyWith(
        status:       WhisperUiStatus.error,
        errorMessage: 'Not paired',
      );
      return;
    }

    try {
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      _currentRecordPath = await _local.startRecording(msgId);

      // Record seconds counter
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state.status == WhisperUiStatus.recording) {
          state = state.copyWith(recordSeconds: state.recordSeconds + 1);
        }
      });

      // Amplitude stream → waveform
      await _ampSub?.cancel();
      _ampSub = _local.amplitudeStream.listen((amp) {
        final updated = [...state.amplitudes, amp];
        state = state.copyWith(amplitudes: updated);
      });

      Log.i(_tag, 'PTT started — recording to $_currentRecordPath');
    } catch (e, st) {
      Log.e(_tag, 'PTT start failed', error: e, stack: st);
      state = state.copyWith(
        status:       WhisperUiStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> onPttPressEnd() async {
    if (state.status != WhisperUiStatus.recording) return;
    if (state.recordSeconds < 1) {
      // Too short — cancel
      await _local.stopRecording();
      state = state.copyWith(status: WhisperUiStatus.idle, amplitudes: []);
      Log.w(_tag, 'Recording too short — discarded');
      return;
    }

    _recordTimer?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;

    final durationSecs = state.recordSeconds;
    state = state.copyWith(status: WhisperUiStatus.sending);

    try {
      final recordedPath = await _local.stopRecording();
      if (recordedPath == null) {
        throw Exception('No recording to send');
      }

      final pairingState = ref.read(pairingNotifierProvider);
      final session      = pairingState.session!;
      final authState    = ref.read(authNotifierProvider);
      final myUid        = authState.user.uid;
      final partnerUid   = myUid == session.user1Uid ? session.user2Uid : session.user1Uid;

      final result = await _repo.sendWhisper(
        fromUid:         myUid,
        toUid:           partnerUid,
        toFcmToken:      session.partnerFcmToken(myUid),
        coupleId:        session.coupleId,
        recordedFilePath: recordedPath,
        durationSeconds:  durationSecs,
      );

      result.fold(
        (f) {
          Log.e(_tag, 'sendWhisper failed: ${f.message}');
          state = state.copyWith(
            status:       WhisperUiStatus.error,
            errorMessage: f.message,
          );
        },
        (msg) {
          Log.i(_tag, 'Whisper delivered: ${msg.id}');
          state = state.copyWith(
            status:    WhisperUiStatus.delivered,
            message:   msg,
            amplitudes: [],
          );
          // Auto-reset after 3 s
          Future.delayed(
            const Duration(seconds: 3),
            () => state = state.copyWith(status: WhisperUiStatus.idle),
          );
        },
      );
    } catch (e, st) {
      Log.e(_tag, 'PTT end failed', error: e, stack: st);
      state = state.copyWith(
        status:       WhisperUiStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  // ── Receive: Tap to Listen ────────────────────────────────────────────────

  Future<void> playNextWhisper() async {
    final queue = state.incomingQueue;
    if (queue.isEmpty) return;

    final message = queue.first;
    state = state.copyWith(
      status:  WhisperUiStatus.downloading,
      message: message,
    );

    // Download + decrypt
    final decResult = await _repo.downloadAndDecrypt(message: message);
    decResult.fold(
      (f) {
        state = state.copyWith(
          status:       WhisperUiStatus.error,
          errorMessage: f.message,
        );
      },
      (decPath) async {
        state = state.copyWith(status: WhisperUiStatus.playing);

        final playResult = await _repo.playAndWipe(
          message: message,
          decryptedLocalPath: decPath,
        );

        playResult.fold(
          (f) => state = state.copyWith(
            status:       WhisperUiStatus.error,
            errorMessage: f.message,
          ),
          (_) {
            final remaining = queue.skip(1).toList();
            state = state.copyWith(
              status:        WhisperUiStatus.wiped,
              incomingQueue: remaining,
              message:       message.copyWith(status: WhisperStatus.wiped),
            );
            Log.i(_tag, '✅ Whisper played + wiped: ${message.id}');
          },
        );
      },
    );
  }

  // ── Incoming listener ─────────────────────────────────────────────────────

  void _startIncomingListener() {
    final pairingState = ref.read(pairingNotifierProvider);
    final session      = pairingState.session;
    final authState    = ref.read(authNotifierProvider);
    if (session == null || !authState.isAuthenticated) return;

    final myUid = authState.user.uid;

    _incomingSub?.cancel();
    _incomingSub = _repo
        .watchIncomingWhispers(myUid: myUid, coupleId: session.coupleId)
        .listen((either) {
      either.fold(
        (f) => Log.w(_tag, 'Incoming stream error: ${f.message}'),
        (msg) {
          final already = state.incomingQueue.any((m) => m.id == msg.id);
          if (!already) {
            final updated = [...state.incomingQueue, msg];
            state = state.copyWith(
              incomingQueue: updated,
              status: state.status == WhisperUiStatus.idle
                  ? WhisperUiStatus.receivedNew
                  : state.status,
            );
            Log.i(_tag, '📨 Incoming whisper queued: ${msg.id}');
          }
        },
      );
    });
  }

  void reset() => state = const WhisperUiState();

  void _cleanup() {
    _recordTimer?.cancel();
    _ampSub?.cancel();
    _incomingSub?.cancel();
  }
}

final whisperNotifierProvider =
    NotifierProvider<WhisperNotifier, WhisperUiState>(
  WhisperNotifier.new,
);
