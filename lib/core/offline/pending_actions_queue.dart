// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pending_actions_queue.dart
//  Hive-backed persistent queue for offline action retry.
//
//  Usage:
//   1. Queue.enqueue(PendingAction(...)) when a send fails due to network.
//   2. SyncWorker calls Queue.drainDue() when connectivity is restored.
//   3. After successful retry, call Queue.remove(id).
//   4. Expired actions (>5 retries) are auto-pruned.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/logger.dart';
import 'pending_action.dart';

class PendingActionsQueue {
  static const _tag      = 'PendingQueue';
  static const _boxName  = 'affinity_pending_actions';
  static const _uuid     = Uuid();

  Box<PendingAction>? _box;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(PendingActionAdapter());
    }
    _box = await Hive.openBox<PendingAction>(_boxName);
    await _pruneExpired();
    Log.i(_tag, 'Queue ready: ${_box!.length} pending actions');
  }

  Box<PendingAction> get _b {
    final b = _box;
    if (b == null) throw StateError('PendingActionsQueue not initialised');
    return b;
  }

  // ── Enqueue ───────────────────────────────────────────────────────────────

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final action = PendingAction(
      id:        _uuid.v4(),
      type:      type,
      payload:   payload,
      createdAt: DateTime.now(),
    );
    await _b.put(action.id, action);
    Log.i(_tag, 'Queued ${action.type} action ${action.id}');
  }

  // ── Drain due actions ─────────────────────────────────────────────────────

  /// Returns all actions that are due for retry (not expired, nextRetry past).
  List<PendingAction> drainDue() {
    final due = _b.values
        .where((a) => !a.isExpired && a.isDue)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    Log.i(_tag, '${due.length} actions due for retry');
    return due;
  }

  // ── Update after retry ────────────────────────────────────────────────────

  Future<void> markRetried(String id) async {
    final action = _b.get(id);
    if (action == null) return;
    action.markRetried();
    if (action.isExpired) {
      Log.w(_tag, 'Action $id expired after ${action.retryCount} retries — discarding');
      await _b.delete(id);
    } else {
      await action.save();
      Log.d(_tag, 'Action $id retry ${action.retryCount} scheduled at ${action.nextRetryAt}');
    }
  }

  Future<void> remove(String id) async {
    await _b.delete(id);
    Log.i(_tag, 'Action $id removed from queue (success)');
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  int get length => _b.length;
  bool get isEmpty => _b.isEmpty;
  bool get isNotEmpty => _b.isNotEmpty;

  List<PendingAction> getAll() => _b.values.toList();

  // ── Prune expired entries ─────────────────────────────────────────────────

  Future<void> _pruneExpired() async {
    final expired = _b.values.where((a) => a.isExpired).map((a) => a.id).toList();
    for (final id in expired) {
      await _b.delete(id);
    }
    if (expired.isNotEmpty) {
      Log.w(_tag, 'Pruned ${expired.length} expired actions');
    }
  }

  Future<void> dispose() => Hive.close();
}
