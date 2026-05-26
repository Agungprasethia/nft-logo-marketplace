import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';

class PrimaryButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final Color? backgroundColor;

  const PrimaryButton({
    super.key,
    required this.text,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final defaultBg = backgroundColor ?? AppColors.primary;
    
    return Container(
      width: isFullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        color: onPressed == null ? AppColors.surface : defaultBg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: onPressed == null ? null : AppColors.primaryGradient,
        boxShadow: onPressed == null ? [] : AppShadows.glowPrimary,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: isLoading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            size: 20,
                            color: onPressed == null ? AppColors.textSecondary : AppColors.textPrimary,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          text,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: onPressed == null ? AppColors.textSecondary : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
