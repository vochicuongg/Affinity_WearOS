// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — mood_provider.dart
//  MoodNotifier: manages own mood selection + streams partner's live mood.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pairing/presentation/providers/pairing_provider.dart';
import '../../data/datasources/mood_remote_datasource.dart';
import '../../data/repositories/mood_repository_impl.dart';
import '../../domain/entities/mood_state.dart';
import '../../domain/repositories/i_mood_repository.dart';

// ── Infrastructure ────────────────────────────────────────────────────────

final moodRemoteDSProvider = Provider<MoodRemoteDataSource>((ref) =>
    MoodRemoteDataSource(encryption: ref.read(encryptionServiceProvider)));

final moodRepositoryProvider = Provider<IMoodRepository>(
  (ref) => MoodRepositoryImpl(ref.read(moodRemoteDSProvider)),
);

// ── Partner mood stream ───────────────────────────────────────────────────

/// Streams the partner's live decrypted mood.
final partnerMoodProvider = StreamProvider<MoodState?>((ref) async* {
  final pairingState = ref.watch(pairingNotifierProvider);
  final session      = pairingState.session;
  final authState    = ref.watch(authNotifierProvider);

  if (session == null || !authState.isAuthenticated) {
    yield null;
    return;
  }

  final myUid      = authState.user.uid;
  final partnerUid = myUid == session.user1Uid ? session.user2Uid : session.user1Uid;
  final repo       = ref.read(moodRepositoryProvider);

  await for (final either in repo.watchPartnerMood(partnerUid, session.coupleId)) {
    yield either.fold((_) => null, (m) => m);
  }
});

// ── My mood (own selection state machine) ─────────────────────────────────

class MyMoodState {
  const MyMoodState({
    this.selected = AffinityMood.neutral,
    this.isSaving = false,
    this.errorMessage,
  });

  final AffinityMood selected;
  final bool isSaving;
  final String? errorMessage;

  MyMoodState copyWith({
    AffinityMood? selected,
    bool? isSaving,
    String? errorMessage,
  }) =>
      MyMoodState(
        selected:     selected     ?? this.selected,
        isSaving:     isSaving     ?? this.isSaving,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

class MoodNotifier extends Notifier<MyMoodState> {
  static const _tag = 'MoodNotifier';

  @override
  MyMoodState build() {
    // Load last saved mood on init
    _loadInitialMood();
    return const MyMoodState();
  }

  IMoodRepository get _repo => ref.read(moodRepositoryProvider);

  Future<void> _loadInitialMood() async {
    final pairingState = ref.read(pairingNotifierProvider);
    final session      = pairingState.session;
    final authState    = ref.read(authNotifierProvider);
    if (session == null || !authState.isAuthenticated) return;

    final result = await _repo.getMyMood(
      authState.user.uid, session.coupleId);
    result.fold(
      (_) {},
      (mood) => state = state.copyWith(selected: mood),
    );
  }

  /// Persists [mood] to Firestore (encrypted) and updates local state.
  Future<void> selectMood(AffinityMood mood) async {
    state = state.copyWith(selected: mood, isSaving: true);

    final pairingState = ref.read(pairingNotifierProvider);
    final session      = pairingState.session;
    final authState    = ref.read(authNotifierProvider);

    if (session == null || !authState.isAuthenticated) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Not paired',
      );
      return;
    }

    final result = await _repo.updateMood(
      uid:      authState.user.uid,
      coupleId: session.coupleId,
      mood:     mood,
    );

    result.fold(
      (f) {
        Log.e(_tag, 'selectMood failed: ${f.message}');
        state = state.copyWith(isSaving: false, errorMessage: f.message);
      },
      (_) {
        Log.i(_tag, 'Mood set to ${mood.label}');
        state = state.copyWith(isSaving: false, errorMessage: null);
      },
    );
  }
}

final moodNotifierProvider = NotifierProvider<MoodNotifier, MyMoodState>(
  MoodNotifier.new,
);

// ── Partner accent color (derived) ────────────────────────────────────────

/// Returns the partner's current mood Color, or the default accent if no mood.
/// Used by the tile screen to tint the heartbeat ring.
final partnerAccentColorProvider = Provider<Color>((ref) {
  final moodAsync = ref.watch(partnerMoodProvider);
  return moodAsync.when(
    data:    (m) => m?.color ?? const Color(0xFFE8305A),
    loading: ()  => const Color(0xFFE8305A),
    error:   (err, st) => const Color(0xFFE8305A),
  );
});
