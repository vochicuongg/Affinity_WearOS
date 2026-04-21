// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — affinity_button.dart
//  Circular action button sized for Wear OS tap targets (min 48×48dp).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A circular icon button styled with the Affinity rose glow aesthetic.
class AffinityButton extends StatelessWidget {
  const AffinityButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 56.0,
    this.color = AppTheme.accent,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed != null ? color : AppTheme.onDisabled,
            boxShadow: onPressed != null
                ? [
                    BoxShadow(
                      color: AppTheme.accentGlow,
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: AppTheme.onBackground,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}
