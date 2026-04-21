// ═══════════════════════════════════════════════════════════════════════════
//  Affinity — app_theme.dart
//  Design system for Wear OS AMOLED circular display.
//
//  Palette philosophy:
//   • True black (#000000) background → every off-pixel saves battery on OLED
//   • Deep rose / crimson accent → emotional intimacy branding
//   • Muted surface colours → readable in dim environments / ambient mode
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

abstract final class AppTheme {
  // ── Brand Colours ────────────────────────────────────────────────────────
  static const Color backgroundPure = Color(0xFF000000);   // AMOLED true black
  static const Color surfaceDark    = Color(0xFF0D0D0D);   // Slightly lifted surface
  static const Color surfaceCard    = Color(0xFF1A1A1A);   // Card backgrounds

  static const Color accent         = Color(0xFFE8305A);   // Deep rose — primary CTA
  static const Color accentSoft     = Color(0xFFFF6B8A);   // Lighter rose — icons/text
  static const Color accentGlow     = Color(0x33E8305A);   // Rose with 20% opacity — glows

  static const Color onBackground   = Color(0xFFF0F0F0);   // Primary text
  static const Color onSurface      = Color(0xFFBBBBBB);   // Secondary text
  static const Color onDisabled     = Color(0xFF555555);   // Disabled / ambient

  static const Color success        = Color(0xFF4CAF82);   // Paired / connected
  static const Color warning        = Color(0xFFFFB547);   // Pairing in-progress
  static const Color error          = Color(0xFFE84747);   // Error states

  // ── Typography ───────────────────────────────────────────────────────────
  // Compact, high-legibility type scale for 40–45 mm round watch displays.
  static const TextTheme _textTheme = TextTheme(
    // Large status labels (e.g., "PAIRED", "CONNECTING")
    displaySmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: onBackground,
    ),
    // Section titles
    titleMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: onBackground,
    ),
    // Body / status text
    bodyMedium: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: onSurface,
    ),
    // Small captions
    labelSmall: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.8,
      color: onDisabled,
    ),
  );

  // ── Dark Theme ───────────────────────────────────────────────────────────
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // Colour scheme
    colorScheme: const ColorScheme.dark(
      surface: backgroundPure,
      primary: accent,
      onPrimary: onBackground,
      secondary: accentSoft,
      onSecondary: backgroundPure,
      error: error,
      onError: onBackground,
    ),
    scaffoldBackgroundColor: backgroundPure,

    // Text
    textTheme: _textTheme,

    // App bar (rarely used on watch, but included for consistency)
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundPure,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: onBackground,
        letterSpacing: 0.5,
      ),
    ),

    // Elevated button — used for Tile action buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onBackground,
        minimumSize: const Size(80, 36),
        shape: const StadiumBorder(),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    ),

    // Icon theme
    iconTheme: const IconThemeData(color: accentSoft, size: 20),

    // Splash / highlight — subtler on watch
    splashFactory: InkRipple.splashFactory,
  );
}
