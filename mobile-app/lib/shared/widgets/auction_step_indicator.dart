import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

class AuctionStepIndicator extends StatelessWidget {
  final int currentStep; // 0: Place Bid, 1: Win Auction, 2: Complete Payment, 3: Claim NFT

  const AuctionStepIndicator({super.key, required this.currentStep});

  static const _steps = ['Place Bid', 'Win Auction', 'Pay', 'Claim NFT'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepIndex = index ~/ 2;
            final isCompleted = stepIndex < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 20),
                color: isCompleted ? AppColors.primary : AppColors.border,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final isActive = stepIndex == currentStep;
          final isCompleted = stepIndex < currentStep;

          return Flexible(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : isCompleted
                            ? AppColors.primary
                            : AppColors.surfaceLight,
                    border: Border.all(
                      color: isActive || isCompleted
                          ? AppColors.primary
                          : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text(
                            '${stepIndex + 1}',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: isActive
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _steps[stepIndex],
                  style: AppTextStyles.caption.copyWith(
                    color: isActive || isCompleted
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
