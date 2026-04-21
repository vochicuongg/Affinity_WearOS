// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — mood_color_picker.dart
//  Circular mood palette for Wear OS round watch faces.
//
//  Layout: 8 mood "petals" arranged in a circle around a centre dot.
//  Tap a petal to select that mood. Selected petal pulses with a glow ring.
//  The centre shows the currently selected mood emoji.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../domain/entities/mood_state.dart';
import '../providers/mood_provider.dart';

class MoodColorPicker extends ConsumerStatefulWidget {
  const MoodColorPicker({super.key});

  @override
  ConsumerState<MoodColorPicker> createState() => _MoodColorPickerState();
}

class _MoodColorPickerState extends ConsumerState<MoodColorPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glowOpacity = Tween<double>(begin: 0.3, end: 0.85).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moodState = ref.watch(moodNotifierProvider);
    final selected  = moodState.selected;
    final isSaving  = moodState.isSaving;
    final moods     = AffinityMood.values;

    return SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Mood petals ────────────────────────────────────────────────
          ...List.generate(moods.length, (i) {
            final mood     = moods[i];
            final angle    = (2 * math.pi / moods.length) * i - math.pi / 2;
            const radius   = 68.0;
            final dx       = math.cos(angle) * radius;
            final dy       = math.sin(angle) * radius;
            final isActive = mood == selected;

            return Transform.translate(
              offset: Offset(dx, dy),
              child: AnimatedBuilder(
                animation: _glowOpacity,
                builder: (_, child) => GestureDetector(
                  onTap: isSaving
                      ? null
                      : () => ref
                          .read(moodNotifierProvider.notifier)
                          .selectMood(mood),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width:  isActive ? 38 : 32,
                    height: isActive ? 38 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mood.color,
                      border: isActive
                          ? Border.all(
                              color: mood.color
                                  .withValues(alpha: _glowOpacity.value),
                              width: 2.5,
                            )
                          : Border.all(
                              color: AppTheme.onDisabled.withValues(alpha: 0.3),
                              width: 1,
                            ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: mood.color
                                    .withValues(alpha: _glowOpacity.value * 0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            );
          }),

          // ── Centre: selected mood emoji + save indicator ───────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isSaving
                ? SizedBox(
                    key: const ValueKey('saving'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: selected.color,
                    ),
                  )
                : GestureDetector(
                    key: ValueKey(selected),
                    onTap: () => ref
                        .read(moodNotifierProvider.notifier)
                        .selectMood(selected),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceCard,
                        border: Border.all(
                          color: selected.color.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          selected.emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
