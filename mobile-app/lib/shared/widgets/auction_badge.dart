import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

enum BadgeType { live, frozen, ended, success, neutral }

class AuctionBadge extends StatelessWidget {
  final String text;
  final BadgeType type;

  const AuctionBadge({
    super.key,
    required this.text,
    this.type = BadgeType.neutral,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor = AppColors.textPrimary;

    switch (type) {
      case BadgeType.live:
        bgColor = AppColors.success.withValues(alpha: 0.2);
        textColor = AppColors.success;
        break;
      case BadgeType.frozen:
        bgColor = AppColors.frozen.withValues(alpha: 0.2);
        textColor = AppColors.frozen;
        break;
      case BadgeType.ended:
        bgColor = AppColors.danger.withValues(alpha: 0.2);
        textColor = AppColors.danger;
        break;
      case BadgeType.success:
        bgColor = AppColors.primary.withValues(alpha: 0.2);
        textColor = AppColors.accent;
        break;
      case BadgeType.neutral:
        bgColor = AppColors.surface;
        textColor = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: textColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.labelMedium.copyWith(
          color: textColor,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
