// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — pairing_screen.dart
//  Wear OS Pairing UI — compact, circular, zero-keyboard interaction.
//
//  States:
//   idle         → Pair Device button
//   generatingCode / awaitingPartner → Show large 6-digit code
//   enteringCode → Radial numpad (3 columns × 4 rows, compact)
//   verifying    → Spinner
//   paired       → Success pulse
//   error        → Error message + retry
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/affinity_button.dart';
import '../../../../shared/widgets/circular_watch_scaffold.dart';
import '../providers/pairing_provider.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);

    // Initialise the user's Firestore profile once the screen loads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pairingNotifierProvider.notifier).initializeProfile();
    });
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pairingNotifierProvider);

    // Trigger success animation when paired.
    if (state.status == PairingStatus.paired && !_successCtrl.isCompleted) {
      _successCtrl.forward();
    }

    return CircularWatchScaffold(
      child: _buildBody(state),
    );
  }

  Widget _buildBody(PairingState state) {
    return switch (state.status) {
      PairingStatus.idle ||
      PairingStatus.initializingProfile  => _IdleView(state: state),
      PairingStatus.generatingCode       => _LoadingView(label: 'GENERATING...'),
      PairingStatus.awaitingPartner      => _ShowCodeView(code: state.pairCode ?? '------'),
      PairingStatus.enteringCode         => _EnterCodeView(state: state),
      PairingStatus.verifying            => _LoadingView(label: 'VERIFYING...'),
      PairingStatus.paired               => _PairedView(scale: _successScale),
      PairingStatus.error                => _ErrorView(message: state.errorMessage ?? 'Error'),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Idle — show two options: generate code or enter code
// ─────────────────────────────────────────────────────────────────────────────

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.state});
  final PairingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = state.status == PairingStatus.initializingProfile;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'PAIR DEVICE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: AppTheme.onDisabled,
          ),
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
          )
        else ...[
          AffinityButton(
            icon: Icons.qr_code_rounded,
            onPressed: () =>
                ref.read(pairingNotifierProvider.notifier).generateCode(),
            size: 48,
            tooltip: 'Show my code',
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                ref.read(pairingNotifierProvider.notifier).switchToEnterCode(),
            child: const Text(
              'Enter code',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.accentSoft,
                decoration: TextDecoration.underline,
                decorationColor: AppTheme.accentSoft,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Show Code — display the 6-digit code large for partner to enter
// ─────────────────────────────────────────────────────────────────────────────

class _ShowCodeView extends ConsumerWidget {
  const _ShowCodeView({required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Split into two groups of 3 for readability: "123 456"
    final left  = code.length >= 3 ? code.substring(0, 3) : code;
    final right = code.length >= 6 ? code.substring(3, 6) : '';

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'YOUR CODE',
                style: TextStyle(fontSize: 9, letterSpacing: 2, color: AppTheme.onDisabled),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    left,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.onBackground,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    right,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Waiting for partner...',
                style: TextStyle(fontSize: 9, color: AppTheme.onDisabled),
              ),
            ],
          ),
        ),
        // ── Back button ─────────────────────────────────────
        Positioned(
          top: 28,
          left: 28,
          child: GestureDetector(
            onTap: () => ref.read(pairingNotifierProvider.notifier).reset(),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Enter Code — compact Wear OS numpad (no hardware keyboard on watch)
// ─────────────────────────────────────────────────────────────────────────────

class _EnterCodeView extends ConsumerWidget {
  const _EnterCodeView({required this.state});
  final PairingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pairingNotifierProvider.notifier);
    final code = state.enteredCode.padRight(6, '·');

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Code display ─────────────────────────────────────────────
              Text(
                '${code.substring(0, 3)} ${code.substring(3)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 5,
                  color: AppTheme.onBackground,
                ),
              ),
              const SizedBox(height: 8),
              // ── Numpad 3×4 ───────────────────────────────────────────────
              SizedBox(
                width: 130,
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.2,
                  children: [
                    for (final d in ['1','2','3','4','5','6','7','8','9','','0','⌫'])
                      _NumKey(
                        label: d,
                        onTap: d == '⌫'
                            ? notifier.deleteDigit
                            : d.isEmpty
                                ? null
                                : () => notifier.appendDigit(d),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // ── Back button ─────────────────────────────────────
        Positioned(
          top: 28,
          left: 28,
          child: GestureDetector(
            onTap: () => notifier.reset(),
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
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: onTap != null ? AppTheme.surfaceCard : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: label == '⌫' ? AppTheme.accentSoft : AppTheme.onBackground,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Loading, Paired, Error states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(fontSize: 9, letterSpacing: 1.5, color: AppTheme.onDisabled)),
    ],
  );
}

class _PairedView extends StatelessWidget {
  const _PairedView({required this.scale});
  final Animation<double> scale;

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: scale,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 60, height: 60,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.success,
          ),
          child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 8),
        const Text(
          'PAIRED!',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppTheme.success),
        ),
      ],
    ),
  );
}

class _ErrorView extends ConsumerWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pick icon based on whether it's a connectivity issue.
    final isNetworkError = message.toLowerCase().contains('internet') ||
        message.toLowerCase().contains('connection') ||
        message.toLowerCase().contains('wifi') ||
        message.toLowerCase().contains('server');

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isNetworkError ? Icons.wifi_off_rounded : Icons.error_outline,
          color: AppTheme.error,
          size: 28,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: AppTheme.onSurface),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => ref.read(pairingNotifierProvider.notifier).reset(),
          child: const Text('Retry', style: TextStyle(fontSize: 10, color: AppTheme.accentSoft)),
        ),
      ],
    );
  }
}
