import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';

class AppShadows {
  static final List<BoxShadow> soft = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> medium = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> cardElevated = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  static final List<BoxShadow> glowPrimary = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.4),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> glowSuccess = [
    BoxShadow(
      color: AppColors.success.withValues(alpha: 0.4),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> glowDanger = [
    BoxShadow(
      color: AppColors.danger.withValues(alpha: 0.4),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> glowFrozen = [
    BoxShadow(
      color: AppColors.frozen.withValues(alpha: 0.4),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];

  static final List<BoxShadow> glowAccent = [
    BoxShadow(
      color: AppColors.accent.withValues(alpha: 0.3),
      blurRadius: 20,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];
}
