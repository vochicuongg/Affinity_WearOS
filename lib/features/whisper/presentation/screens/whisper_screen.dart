// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — whisper_screen.dart
//  Full-screen Whisper PTT overlay for the circular Wear OS display.
//
//  Activated by the 🎤 quick-action button on the tile.
//  Centred layout: partner name (top arc) → waveform → PTT button → label
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/circular_watch_scaffold.dart';
import '../../../mood/presentation/providers/mood_provider.dart';
import '../../../pairing/presentation/providers/pairing_provider.dart';
import '../providers/whisper_provider.dart';
import '../widgets/whisper_ptt_button.dart';

class WhisperScreen extends ConsumerWidget {
  const WhisperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing      = ref.watch(pairingNotifierProvider);
    final accentColor  = ref.watch(partnerAccentColorProvider);
    final whisperState = ref.watch(whisperNotifierProvider);

    // Partner display name (from pairing session)
    final partnerLabel = pairing.session != null ? '♥ Partner' : 'Not Paired';

    return CircularWatchScaffold(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Back button (top-left) ─────────────────────────────────────
          Positioned(
            top: 28,
            left: 28,
            child: GestureDetector(
              onTap: () {
                ref.read(whisperNotifierProvider.notifier).reset();
                Navigator.of(context).pop();
              },
              child: Container(
                width:  28,
                height: 28,
                decoration: BoxDecoration(
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

          // ── Partner label (top arc) ────────────────────────────────────
          Positioned(
            top: 34,
            child: Text(
              partnerLabel,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppTheme.onDisabled,
              ),
            ),
          ),

          // ── Privacy badge: whisper volume indicator ────────────────────
          Positioned(
            bottom: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.volume_down_rounded, size: 10, color: AppTheme.onDisabled),
                const SizedBox(width: 3),
                Text(
                  'WHISPER MODE  35%',
                  style: const TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.0,
                    color: AppTheme.onDisabled,
                  ),
                ),
              ],
            ),
          ),

          // ── Incoming count badge ───────────────────────────────────────
          if (whisperState.incomingQueue.length > 1)
            Positioned(
              top: 58,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '${whisperState.incomingQueue.length} messages',
                  style: TextStyle(
                    fontSize: 8,
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // ── Main PTT button ────────────────────────────────────────────
          WhisperPttButton(accentColor: accentColor),
        ],
      ),
    );
  }
}
