// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — sync_worker.dart
//  WorkManager integration for offline retry of failed Haptic/Mood sends.
//
//  Architecture:
//   • On network restore → ConnectivityService triggers an immediate sync.
//   • WorkManager schedules a periodic background task every 15 min
//     as a fallback (even when the app is in the background).
//   • The worker reads the PendingActionsQueue, replays each action,
//     and removes successful ones.
//
//  WorkManager task name: 'affinityPendingSync'
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/logger.dart';
import 'connectivity_service.dart';
import 'pending_action.dart';
import 'pending_actions_queue.dart';

// ── WorkManager task dispatcher ───────────────────────────────────────────────

/// Called by WorkManager in a background isolate.
/// Must be a top-level function annotated with @pragma.
@pragma('vm:entry-point')
void workManagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    const tag = 'SyncWorker[BG]';
    Log.i(tag, 'Background task: $taskName');

    try {
      final queue = PendingActionsQueue();
      await queue.init();

      await _replayActions(queue, tag);
      return true;
    } catch (e, st) {
      Log.e(tag, 'Background sync failed', error: e, stack: st);
      return false;
    }
  });
}

// ── SyncWorker ────────────────────────────────────────────────────────────────

class SyncWorker {
  static const _tag          = 'SyncWorker';
  static const _bgTaskName   = 'affinityPendingSync';
  static const _bgTaskUnique = 'affinity_bg_sync';

  final PendingActionsQueue _queue;
  final ConnectivityService _connectivity;
  StreamSubscription<AffinityConnectivity>? _connectSub;

  SyncWorker(this._queue, this._connectivity);

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> init() async {
    // ① Register WorkManager background task (periodic fallback)
    await Workmanager().initialize(
      workManagerCallbackDispatcher,
    );

    await Workmanager().registerPeriodicTask(
      _bgTaskUnique,
      _bgTaskName,
      frequency:          const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );

    Log.i(_tag, 'WorkManager periodic task registered (15 min)');

    // ② React immediately when connectivity is restored
    _connectSub = _connectivity.onChanged.listen((state) {
      if (state == AffinityConnectivity.online) {
        Log.i(_tag, 'Connectivity restored — running immediate sync');
        sync();
      }
    });

    Log.i(_tag, 'SyncWorker initialised');
  }

  // ── Foreground sync ───────────────────────────────────────────────────────

  Future<void> sync() async {
    if (_connectivity.isOffline) {
      Log.d(_tag, 'Skipping sync — device offline');
      return;
    }

    if (_queue.isEmpty) {
      Log.d(_tag, 'Queue empty — nothing to sync');
      return;
    }

    Log.i(_tag, 'Starting sync: ${_queue.length} pending actions');
    await _replayActions(_queue, _tag);
  }

  Future<void> dispose() async {
    await _connectSub?.cancel();
  }
}

// ── Shared replay logic ───────────────────────────────────────────────────────

Future<void> _replayActions(PendingActionsQueue queue, String tag) async {
  final due = queue.drainDue();
  for (final action in due) {
    try {
      await _executeAction(action);
      await queue.remove(action.id);
      Log.i(tag, '✅ Replayed ${action.type}: ${action.id}');
    } catch (e) {
      Log.w(tag, '⚠️ Retry failed for ${action.id}: $e');
      await queue.markRetried(action.id);
    }
  }
}

/// Executes a single pending action. Supports haptic and mood types.
/// Whisper is NOT retried (audio files are wiped immediately after failure).
Future<void> _executeAction(PendingAction action) async {
  final payload  = action.payload;
  final db       = FirebaseFirestore.instance;

  switch (action.type) {
    case PendingActionType.haptic:
      final coupleId  = payload['coupleId']  as String;
      final signalId  = payload['signalId']  as String;
      final fromUid   = payload['fromUid']   as String;
      final nonce     = payload['nonce']     as String;
      await db
          .collection('couples')
          .doc(coupleId)
          .collection('signals')
          .add({
            'fromUid':   fromUid,
            'signal':    signalId,
            'nonce':     nonce,
            'ts':        Timestamp.now(),
            'replayed':  true,
          });

    case PendingActionType.mood:
      // Mood is re-sent via its own encrypted write — stub for full integration
      Log.d('Replay', 'Mood retry for ${payload['uid']} — requires re-encryption');
      throw UnimplementedError('Mood retry requires session key — skip for now');

    default:
      throw UnimplementedError('Unknown action type: ${action.type}');
  }
}

// ── Riverpod providers ────────────────────────────────────────────────────────

final pendingActionsQueueProvider = Provider<PendingActionsQueue>(
  (_) => PendingActionsQueue(),
);

final connectivityServiceProvider = Provider<ConnectivityService>(
  (_) => ConnectivityService(),
);

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  return SyncWorker(
    ref.read(pendingActionsQueueProvider),
    ref.read(connectivityServiceProvider),
  );
});
