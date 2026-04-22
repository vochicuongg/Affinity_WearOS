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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _MoodPickerPage(),
      ),
    );
  }

  void _showLoveSignalPicker() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LoveSignalPage(
          onSelected: (signal) {
            Navigator.pop(context);
            ref.read(hapticNotifierProvider.notifier).sendSignal(signal);
          },
        ),
      ),
    );
  }

  void _showUnpairDialog() {
    WatchHaptics.medium();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        titlePadding: const EdgeInsets.only(top: 24, bottom: 8),
        contentPadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.only(bottom: 8),
        title: const Text(
          'Unpair device?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppTheme.onSurface),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppTheme.onDisabled),
            onPressed: () => Navigator.pop(context),
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded, color: AppTheme.error),
            onPressed: () {
              Navigator.pop(context);
              ref.read(pairingNotifierProvider.notifier).unpair();
            },
          ),
        ],
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
            radius: 64,
            onTap: _onHapticTap,
          ),
          _QuickActionButton(
            icon: Icons.palette_outlined,
            label: 'Mood',
            angleDeg: 90,     // Right
            radius: 64,
            onTap: _onMoodTap,
          ),
          _QuickActionButton(
            icon: Icons.mic_none_rounded,
            label: 'Whisper',
            angleDeg: 180,    // Bottom
            radius: 64,
            onTap: _onAudioTap,
          ),
          _QuickActionButton(
            icon: Icons.near_me_outlined,
            label: 'Proximity',
            angleDeg: 270,    // Left
            radius: 64,
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
            bottom: 16,
            child: GestureDetector(
              onLongPress: connectionState == _ConnectionState.paired
                  ? _showUnpairDialog
                  : null,
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
          ),

          // ── App name (top arc) ───────────────────────────────────────
          const Positioned(
            top: 18,
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
              bottom: 6,
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
//  Mood Picker Page — full-screen, round-aware layout.
// ─────────────────────────────────────────────────────────────────────────────

class _MoodPickerPage extends StatelessWidget {
  const _MoodPickerPage();

  @override
  Widget build(BuildContext context) {
    return CircularWatchScaffold(
      child: Stack(
        children: [
          // ── Main content (centred) ────────────────────────────────────
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16), // Push content down to avoid back button
                const Text(
                  'YOUR MOOD',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onDisabled,
                  ),
                ),
                const SizedBox(height: 4),
                const SizedBox(
                  width: 130, // Reduced from 160 to avoid overlap
                  height: 130,
                  child: FittedBox(child: MoodColorPicker()),
                ),
              ],
            ),
          ),
          // ── Back button (top-left) ────────────────────────────────────
          Positioned(
            top: 28,
            left: 28,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceCard,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.onSurface,
                  size: 14,
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
//  Love Signal Page — full-screen, curved-scroll Wear OS layout.
//  Items indent horizontally near the top/bottom to follow the round bezel.
// ─────────────────────────────────────────────────────────────────────────────

class _LoveSignalPage extends StatelessWidget {
  const _LoveSignalPage({required this.onSelected});
  final ValueChanged<LoveSignal> onSelected;

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
    final screenSize = MediaQuery.of(context).size;
    final itemCount = _signals.length + 2; // +1 header, +1 bottom padding

    return CircularWatchScaffold(
      child: Stack(
        children: [
          // ── Scrollable list ────────────────────────────────────────────
          ListView.builder(
            padding: const EdgeInsets.only(top: 48, bottom: 20), // Clear back button at the top
            itemCount: itemCount,
            itemBuilder: (context, index) {
              // ── Straight vertical padding ──────────
              const double hPad = 28.0; 

              // ── Header ──────────────────────────────────────────────
              if (index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(
                      'SEND SIGNAL',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onDisabled,
                      ),
                    ),
                  ),
                );
              }

              // ── Bottom spacer ───────────────────────────────────────
              if (index == itemCount - 1) {
                return const SizedBox(height: 20);
              }

              // ── Signal row ─────────────────────────────────────────
              final signal = _signals[index - 1];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: hPad),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(signal),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(
                          signal.displayName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: AppTheme.onDisabled,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // ── Back button (top-left) ────────────────────────────────────
          Positioned(
            top: 28,
            left: 28,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceCard,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.onSurface,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
