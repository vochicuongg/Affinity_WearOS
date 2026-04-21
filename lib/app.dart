// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — app.dart  (Phase 2 update)
//  Auth-aware routing: loading → pairing → tile (home).
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/pairing/presentation/providers/pairing_provider.dart';
import 'features/pairing/presentation/screens/pairing_screen.dart';
import 'features/tile/presentation/wear_os_tile_screen.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/circular_watch_scaffold.dart';

class WearApp extends ConsumerWidget {
  const WearApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Affinity',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _AppRouter(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
    );
  }
}

// ── Routing logic ─────────────────────────────────────────────────────────

class _AppRouter extends ConsumerWidget {
  const _AppRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState   = ref.watch(authNotifierProvider);
    final isPaired    = ref.watch(isPairedProvider);

    return switch (authState.status) {
      // ── Loading / signing in ────────────────────────────────────────
      AuthStatus.initial || AuthStatus.loading => CircularWatchScaffold(
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
              SizedBox(height: 10),
              Text(
                'AFFINITY',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onDisabled,
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Authenticated: route on paired status ───────────────────────
      AuthStatus.authenticated => isPaired
          ? const WearOsTileScreen()
          : const PairingScreen(),

      // ── Auth error / not authenticated ──────────────────────────────
      AuthStatus.unauthenticated || AuthStatus.error => CircularWatchScaffold(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppTheme.error, size: 24),
            const SizedBox(height: 8),
            const Text(
              'Sign-in failed',
              style: TextStyle(fontSize: 10, color: AppTheme.onSurface),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () =>
                  ref.read(authNotifierProvider.notifier).retrySignIn(),
              child: const Text(
                'Retry',
                style: TextStyle(fontSize: 10, color: AppTheme.accentSoft),
              ),
            ),
          ],
        ),
      ),
    };
  }
}
