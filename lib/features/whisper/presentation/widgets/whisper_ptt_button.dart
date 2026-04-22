// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_ptt_button.dart
//  "Hold to Talk" button with integrated waveform display.
//
//  UX states:
//   • idle        → mic icon, rose glow ring
//   • recording   → waveform replaces icon, ring pulses red, timer shows
//   • sending     → spinner
//   • delivered   → checkmark (auto-resets after 3 s)
//   • receivedNew → pulsing earphone icon — tap to listen
//   • playing     → waveform with playback colour
//   • error       → red X with error text
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/audio/waveform_painter.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/watch_haptics.dart';
import '../providers/whisper_provider.dart';

class WhisperPttButton extends ConsumerStatefulWidget {
  const WhisperPttButton({super.key, this.accentColor});
  final Color? accentColor; // partner's mood color (optional tint)

  @override
  ConsumerState<WhisperPttButton> createState() => _WhisperPttButtonState();
}

class _WhisperPttButtonState extends ConsumerState<WhisperPttButton>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final Animation<double>   _ringScale;
  late final Animation<double>   _ringOpacity;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _ringScale   = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut));
    _ringOpacity = Tween<double>(begin: 0.4, end: 0.9)
        .animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  Color get _accent => widget.accentColor ?? AppTheme.accent;

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(whisperNotifierProvider);
    final notifier = ref.read(whisperNotifierProvider.notifier);

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // ── Waveform (overlaid above button when recording/playing) ────
        if (ws.isRecording || ws.status == WhisperUiStatus.playing)
          Positioned(
            top: -52,
            child: WaveformWidget(
              key: const ValueKey('waveform'),
              data: WaveformData(
                amplitudes:  ws.amplitudes,
                isActive:    ws.isRecording,
                accentColor: _accent,
              ),
              width:  160,
              height: 44,
            ),
          ),

        // ── Main PTT button (centred) ──────────────────────────────────
        GestureDetector(
          onLongPressStart: (_) async {
            await WatchHaptics.medium(); // Phase 6: tactile start
            notifier.onPttPressStart();
          },
          onLongPressEnd: (_) async {
            await WatchHaptics.success(); // Phase 6: tactile end
            notifier.onPttPressEnd();
          },
          onTap: ws.status == WhisperUiStatus.receivedNew
              ? () => notifier.playNextWhisper()
              : null,
          child: AnimatedBuilder(
            animation: _ringCtrl,
            builder: (_, child) {
              final isActive = ws.isRecording ||
                  ws.status == WhisperUiStatus.receivedNew;
              return Transform.scale(
                scale: isActive ? _ringScale.value : 1.0,
                child: Container(
                  width:  72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _buttonColor(ws.status),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withValues(
                          alpha: isActive ? _ringOpacity.value * 0.5 : 0.2,
                        ),
                        blurRadius: isActive ? 20 : 10,
                        spreadRadius: isActive ? 4 : 0,
                      ),
                    ],
                  ),
                  child: Center(child: _buttonContent(ws)),
                ),
              );
            },
          ),
        ),

        // ── Timer / label under button ─────────────────────────────────
        Positioned(
          bottom: -28,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _buildLabel(ws),
          ),
        ),
      ],
    );
  }

  Color _buttonColor(WhisperUiStatus status) => switch (status) {
        WhisperUiStatus.recording   => AppTheme.error.withValues(alpha: 0.85),
        WhisperUiStatus.sending     => AppTheme.surfaceCard,
        WhisperUiStatus.delivered   => AppTheme.success,
        WhisperUiStatus.receivedNew => _accent,
        WhisperUiStatus.playing     => _accent.withValues(alpha: 0.7),
        WhisperUiStatus.error       => AppTheme.error,
        WhisperUiStatus.wiped       => AppTheme.surfaceDark,
        _                           => AppTheme.surfaceCard,
      };

  Widget _buttonContent(WhisperUiState ws) => switch (ws.status) {
        WhisperUiStatus.recording =>
          const Icon(Icons.fiber_manual_record, color: Colors.white, size: 32),
        WhisperUiStatus.sending =>
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accentSoft,
            ),
          ),
        WhisperUiStatus.delivered =>
          const Icon(Icons.check_rounded, color: Colors.white, size: 30),
        WhisperUiStatus.receivedNew =>
          const Icon(Icons.hearing_rounded, color: Colors.white, size: 28),
        WhisperUiStatus.downloading =>
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white,
            ),
          ),
        WhisperUiStatus.playing =>
          const Icon(Icons.volume_up_rounded, color: Colors.white, size: 26),
        WhisperUiStatus.error =>
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 28),
        WhisperUiStatus.wiped =>
          const Icon(Icons.delete_sweep_rounded, color: AppTheme.onDisabled, size: 24),
        _ =>
          const Icon(Icons.mic_none_rounded, color: AppTheme.accentSoft, size: 30),
      };

  Widget _buildLabel(WhisperUiState ws) {
    final style = const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.0,
      color: AppTheme.onSurface,
    );

    return switch (ws.status) {
      WhisperUiStatus.recording => Text(
          key: const ValueKey('rec'),
          '${ws.recordSeconds}s  RECORDING',
          style: style.copyWith(color: AppTheme.error),
        ),
      WhisperUiStatus.sending => Text(
          key: const ValueKey('sending'),
          'SENDING…',
          style: style,
        ),
      WhisperUiStatus.delivered => Text(
          key: const ValueKey('delivered'),
          'DELIVERED ✓',
          style: style.copyWith(color: AppTheme.success),
        ),
      WhisperUiStatus.receivedNew => Text(
          key: const ValueKey('tap'),
          'TAP TO LISTEN',
          style: style.copyWith(color: _accent),
        ),
      WhisperUiStatus.playing => Text(
          key: const ValueKey('playing'),
          'WHISPERING…',
          style: style.copyWith(color: _accent),
        ),
      WhisperUiStatus.wiped => Text(
          key: const ValueKey('wiped'),
          'MESSAGE WIPED',
          style: style.copyWith(color: AppTheme.onDisabled),
        ),
      WhisperUiStatus.error => Text(
          key: const ValueKey('err'),
          ws.errorMessage ?? 'ERROR',
          style: style.copyWith(color: AppTheme.error),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      _ => Text(
          key: const ValueKey('hold'),
          'HOLD TO TALK',
          style: style,
        ),
    };
  }
}
