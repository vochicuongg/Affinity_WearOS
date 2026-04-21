// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — circular_watch_scaffold.dart  (Phase 6 — Ambient Mode Polish)
//
//  Wear OS guidelines for Always-On Display (AOD):
//   • Black background — OLED pixel power = 0 for black pixels.
//   • Greyscale only — no coloured elements.
//   • No animations — static content only.
//   • Reduced pixel usage — aim for <15% lit pixels.
//   • Interactive elements hidden — no buttons/tappable areas.
//
//  Implementation:
//   • AmbientMode widget detects WearMode.ambient.
//   • WatchShape clips the content to circle/square bezel.
//   • _AmbientScreen: shows time + partner heartbeat icon in pure white/grey.
//   • _InteractiveScreen: full-colour animated content (normal mode).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:wear/wear.dart';

import '../theme/app_theme.dart';

/// Core scaffold used by every screen in Affinity.
///
/// Automatically switches between interactive and ambient layouts.
/// Pass [ambientChild] to override the default greyscale ambient view.
class CircularWatchScaffold extends StatelessWidget {
  const CircularWatchScaffold({
    super.key,
    required this.child,
    this.ambientChild,
    this.backgroundColor = AppTheme.backgroundPure,
    this.ambientTimeLabel,   // e.g. "❤ Paired" for the ambient status line
  });

  final Widget child;
  final Widget? ambientChild;
  final Color backgroundColor;
  final String? ambientTimeLabel;

  @override
  Widget build(BuildContext context) {
    return WatchShape(
      builder: (context, shape, _) {
        return AmbientMode(
          builder: (context, mode, _) {
            final bool isAmbient = mode == WearMode.ambient;
            return Scaffold(
              backgroundColor: isAmbient ? Colors.black : backgroundColor,
              body: _ClippedWatchBody(
                shape: shape,
                child: isAmbient
                    ? (ambientChild ?? _AmbientScreen(statusLabel: ambientTimeLabel))
                    : child,
              ),
            );
          },
        );
      },
    );
  }
}

// ── Bezel clipper ─────────────────────────────────────────────────────────────

class _ClippedWatchBody extends StatelessWidget {
  const _ClippedWatchBody({
    required this.shape,
    required this.child,
  });

  final WearShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isRound = shape == WearShape.round;
    return ClipRRect(
      borderRadius: isRound
          ? BorderRadius.circular(9999)
          : BorderRadius.circular(16),
      child: SizedBox.expand(child: child),
    );
  }
}

// ── Ambient screen ────────────────────────────────────────────────────────────

/// High-contrast, low-pixel-ratio ambient display.
///
/// Shows:
///  • Current time (large, white, centre)
///  • A dim heart icon (partner connected indicator)
///  • Optional [statusLabel] (e.g. "❤ Paired" or "NOT PAIRED")
///
/// Satisfies Wear OS AOD guidelines: <15% lit pixels, no colour, no animation.
class _AmbientScreen extends StatelessWidget {
  const _AmbientScreen({this.statusLabel});
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final now   = TimeOfDay.now();
    final hour  = now.hour.toString().padLeft(2, '0');
    final min   = now.minute.toString().padLeft(2, '0');
    final time  = '$hour:$min';

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Heart icon (very dim — minimal pixels lit)
            const Icon(
              Icons.favorite_rounded,
              size: 16,
              color: Color(0xFF444444),
            ),
            const SizedBox(height: 6),

            // Time
            Text(
              time,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 42,
                fontWeight: FontWeight.w200,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),

            // Status label
            if (statusLabel != null) ...[
              const SizedBox(height: 6),
              Text(
                statusLabel!,
                style: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.8,
                  color: Color(0xFF666666),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
