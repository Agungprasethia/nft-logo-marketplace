import 'package:flutter/material.dart';

class AppColors {
  // ─── Background Colors ───
  static const Color background = Color(0xFF0F0B1F);
  static const Color surface = Color(0xFF17122B);
  static const Color card = Color(0xFF1D1735);
  static const Color surfaceLight = Color(0xFF251E42);

  // ─── Primary Colors ───
  static const Color primary = Color(0xFF7B61FF);
  static const Color secondary = Color(0xFFA855F7);
  static const Color accent = Color(0xFFC084FC);

  // ─── Status Colors ───
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color frozen = Color(0xFF3B82F6);
  static const Color warning = Color(0xFFF59E0B);

  // ─── Semantic Aliases (used across pages) ───
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentRed = Color(0xFFEF4444);
  static const Color frozenBlue = Color(0xFF3B82F6);

  // ─── Text Colors ───
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB8B8C5);

  // ─── Border & Divider ───
  static const Color border = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
  static const Color divider = Color(0x14FFFFFF);

  // ─── Gradients ───
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient subtleGradient = LinearGradient(
    colors: [surface, card],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1A1040),
      Color(0xFF0F0B1F),
      Color(0xFF0F0B1F),
    ],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1D1735),
      Color(0xFF17122B),
    ],
  );

  static LinearGradient glowGradient = LinearGradient(
    colors: [
      primary.withValues(alpha: 0.3),
      secondary.withValues(alpha: 0.1),
    ],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
