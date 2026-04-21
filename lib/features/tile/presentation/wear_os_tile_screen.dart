// ───────────────────────────────────────────────────────────────────────────
//  Affinity — wear_os_tile_screen.dart  (Phase 6 — Grand Finale)
//  Mood tint + Proximity + Whisper PTT + Haptic UI feedback + Ambient mode.
// ───────────────────────────────────────────────────────────────────────────
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptic/haptic_service.dart';
import '../../../core/location/location_service.dart';
import '../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../features/haptic/presentation/providers/haptic_provider.dart';
import '../../../features/mood/presentation/providers/mood_provider.dart';
import '../../../features/mood/presentation/widgets/mood_color_picker.dart';
import '../../../features/pairing/presentation/providers/pairing_provider.dart';
import '../../../features/proximity/presentation/providers/proximity_provider.dart';
import '../../../features/whisper/presentation/screens/whisper_screen.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/watch_haptics.dart';
import '../../../shared/widgets/circular_watch_scaffold.dart';

// ── Connection State ──────────────────────────────────────────────────────
enum _ConnectionState { unpaired, connecting, paired, offBody }

extension _ConnectionStateX on _ConnectionState {
  String get label => switch (this) {
        _ConnectionState.unpaired   => 'NOT PAIRED',
        _ConnectionState.connecting => 'CONNECTING',
        _ConnectionState.paired     => 'CONNECTED',
        _ConnectionState.offBody    => 'OFF WRIST',
      };

  Color get color => switch (this) {
        _ConnectionState.unpaired   => AppTheme.onDisabled,
        _ConnectionState.connecting => AppTheme.warning,
        _ConnectionState.paired     => AppTheme.success,
        _ConnectionState.offBody    => AppTheme.error,
      };

  bool get isPulsing =>
      this == _ConnectionState.paired || this == _ConnectionState.connecting;
}

// ── Derived state provider ────────────────────────────────────────────────

final _tileConnectionStateProvider = Provider<_ConnectionState>((ref) {
  final authState = ref.watch(authNotifierProvider);
  if (authState.status == AuthStatus.loading ||
      authState.status == AuthStatus.initial) {
    return _ConnectionState.connecting;
  }
  if (!authState.isAuthenticated) return _ConnectionState.unpaired;
  final isPaired = ref.watch(isPairedProvider);
  return isPaired ? _ConnectionState.paired : _ConnectionState.unpaired;
});


class WearOsTileScreen extends ConsumerStatefulWidget {
  const WearOsTileScreen({super.key});

  @override
  ConsumerState<WearOsTileScreen> createState() => _WearOsTileScreenState();
}

class _WearOsTileScreenState extends ConsumerState<WearOsTileScreen>
    with TickerProviderStateMixin {
  // ── Heartbeat ring animation ──────────────────────────────────────────
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  // ── Press feedback animation ──────────────────────────────────────────
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    // Heartbeat pulse: scale 1.0 → 1.18, opacity 0.6 → 0.0
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _pulseScale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Centre button press feedback
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  // ── Actions (Phase 3 — wired to Haptic Morse feature) ───────────────

  void _onCentreTap() {
    _pressController.forward().then((_) => _pressController.reverse());
    WatchHaptics.medium();  // Phase 6: tactile confirmation
    // Send the predefined "Heartbeat" signal to the partner.
    ref.read(hapticNotifierProvider.notifier).sendSignal(LoveSignal.heartbeat);
  }

  void _onHapticTap() {
    WatchHaptics.light();   // Phase 6: tactile confirmation
    _showLoveSignalPicker();
  }

  void _onMoodTap() {
    WatchHaptics.tap();     // Phase 6: selection click
    _showMoodPicker();
  }

  void _onAudioTap() {
    WatchHaptics.medium();  // Phase 6: tactile confirmation
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WhisperScreen()),
    );
  }

  void _onProximityTap() => WatchHaptics.tap();

  void _showMoodPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'YOUR MOOD',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w700,
                color: AppTheme.onDisabled,
              ),
            ),
            SizedBox(height: 16),
            MoodColorPicker(),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showLoveSignalPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LoveSignalPicker(
        onSelected: (signal) {
          Navigator.pop(context);
          ref.read(hapticNotifierProvider.notifier).sendSignal(signal);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Phase 2: read real connection state from Riverpod.
    final connectionState = ref.watch(_tileConnectionStateProvider);
    final bool isPulsing  = connectionState.isPulsing;

    // Phase 3: listen for haptic send results (visual toast feedback).
    ref.listen<HapticState>(hapticNotifierProvider, (prev, next) {
      if (next.status == HapticSendStatus.sent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${next.lastSent?.displayName ?? "Signal"} sent!',
              style: const TextStyle(fontSize: 10),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (next.status == HapticSendStatus.error && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.errorMessage ?? 'Send failed',
              style: const TextStyle(fontSize: 10),
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Phase 3: start listening for incoming haptic signals.
    ref.watch(incomingHapticProvider);

    // Phase 4: partner's mood tint colour for the heartbeat ring.
    final partnerAccent  = ref.watch(partnerAccentColorProvider);
    // Phase 4: proximity state (distance label + auto-start tracking when paired).
    final proximityState = ref.watch(proximityNotifierProvider);
    if (connectionState == _ConnectionState.paired &&
        !proximityState.isTracking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(proximityNotifierProvider.notifier).startTracking();
      });
    }

    return CircularWatchScaffold(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Heartbeat ring ───────────────────────────────────────────
          if (isPulsing)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) => Transform.scale(
                scale: _pulseScale.value,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: (connectionState == _ConnectionState.paired
                              ? partnerAccent
                              : connectionState.color)
                          .withValues(alpha: _pulseOpacity.value),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ),

          // ── Four cardinal quick-action buttons ───────────────────────
          _QuickActionButton(
            icon: Icons.vibration,
            label: 'Haptic',
            angleDeg: 0,      // Top
            radius: 72,
            onTap: _onHapticTap,
          ),
          _QuickActionButton(
            icon: Icons.palette_outlined,
            label: 'Mood',
            angleDeg: 90,     // Right
            radius: 72,
            onTap: _onMoodTap,
          ),
          _QuickActionButton(
            icon: Icons.mic_none_rounded,
            label: 'Whisper',
            angleDeg: 180,    // Bottom
            radius: 72,
            onTap: _onAudioTap,
          ),
          _QuickActionButton(
            icon: Icons.near_me_outlined,
            label: 'Proximity',
            angleDeg: 270,    // Left
            radius: 72,
            onTap: _onProximityTap,
          ),

          // ── Centre heartbeat button ──────────────────────────────────
          GestureDetector(
            onTap: _onCentreTap,
            child: AnimatedBuilder(
              animation: _pressController,
              builder: (_, child) => Transform.scale(
                scale: _pressScale.value,
                child: child,
              ),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentGlow,
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppTheme.onBackground,
                  size: 28,
                ),
              ),
            ),
          ),

          // ── Status label (bottom arc) ────────────────────────────────
          Positioned(
            bottom: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                connectionState.label,
                key: ValueKey(connectionState),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color: connectionState.color,
                ),
              ),
            ),
          ),

          // ── App name (top arc) ───────────────────────────────────────
          const Positioned(
            top: 30,
            child: Text(
              'AFFINITY',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 3.0,
                color: AppTheme.onDisabled,
              ),
            ),
          ),

          // ── Proximity distance label (Phase 4) ───────────────────────
          if (proximityState.isTracking)
            Positioned(
              bottom: 18,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(
                  proximityState.level == ProximityLevel.together
                      ? '♥ Together'
                      : proximityState.distanceLabel,
                  key: ValueKey(proximityState.distanceLabel),
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: proximityState.level.shouldVibrate
                        ? partnerAccent.withValues(alpha: 0.9)
                        : AppTheme.onDisabled,
                  ),
                ),
              ),
            ),

        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Quick-action button positioned on a radial arc around the centre.
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.angleDeg,
    required this.radius,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final double angleDeg;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double rad = angleDeg * math.pi / 180;
    final double dx   = math.sin(rad) * radius;
    final double dy   = -math.cos(rad) * radius;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfaceCard,
            border: Border.all(color: AppTheme.accentGlow, width: 1),
          ),
          child: Icon(icon, color: AppTheme.accentSoft, size: 16),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Love Signal Picker — compact Wear OS bottom sheet (no scroll needed).
//  Shows all predefined LoveSignals as tappable rows.
// ─────────────────────────────────────────────────────────────────────────────

class _LoveSignalPicker extends StatelessWidget {
  const _LoveSignalPicker({required this.onSelected});
  final ValueChanged<LoveSignal> onSelected;

  // Exclude `custom` — it's only used for tap-Morse encoded signals.
  static final List<LoveSignal> _signals = [
    LoveSignal.heartbeat,
    LoveSignal.iLoveYou,
    LoveSignal.thinkingOfYou,
    LoveSignal.missYou,
    LoveSignal.goodMorning,
    LoveSignal.goodNight,
    LoveSignal.sos,
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: AppTheme.onDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'SEND SIGNAL',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: AppTheme.onDisabled,
            ),
          ),
          const SizedBox(height: 4),
          ..._signals.map(
            (signal) => _SignalRow(signal: signal, onTap: () => onSelected(signal)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.signal, required this.onTap});
  final LoveSignal signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(signal.displayName, style: const TextStyle(fontSize: 11)),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.onDisabled),
          ],
        ),
      ),
    );
  }
}

