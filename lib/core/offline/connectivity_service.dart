// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — connectivity_service.dart
//  Listens to network changes and triggers the retry queue when online.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../utils/logger.dart';

enum AffinityConnectivity { online, offline }

class ConnectivityService {
  static const _tag = 'ConnectivitySvc';

  final _ctrl = StreamController<AffinityConnectivity>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Stream<AffinityConnectivity> get onChanged => _ctrl.stream;

  AffinityConnectivity _current = AffinityConnectivity.online;
  AffinityConnectivity get current => _current;

  bool get isOnline  => _current == AffinityConnectivity.online;
  bool get isOffline => _current == AffinityConnectivity.offline;

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Read initial state
    final results = await Connectivity().checkConnectivity();
    _current = _toState(results);
    Log.i(_tag, 'Initial connectivity: $_current');

    // Listen for changes
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final newState = _toState(results);
      if (newState != _current) {
        _current = newState;
        Log.i(_tag, 'Connectivity changed → $_current');
        _ctrl.add(_current);
      }
    });
  }

  AffinityConnectivity _toState(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
    return hasNetwork
        ? AffinityConnectivity.online
        : AffinityConnectivity.offline;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _ctrl.close();
  }
}
