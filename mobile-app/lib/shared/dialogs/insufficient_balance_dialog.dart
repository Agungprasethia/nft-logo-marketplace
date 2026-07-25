import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/exceptions/insufficient_balance_exception.dart';

class InsufficientBalanceDialog extends StatelessWidget {
  final InsufficientBalanceException exception;

  const InsufficientBalanceDialog({
    super.key,
    required this.exception,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: AppColors.danger.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: AppShadows.soft,
        ),
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Insufficient Balance',
                        style: AppTextStyles.h3,
                      ),
                      Text(
                        'Cannot complete transaction',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Cost Details
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildRow('Transaction Value', '${exception.transactionValue.toStringAsFixed(4)} ETH'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(color: AppColors.border),
                  ),
                  _buildRow('Estimated Gas', '${exception.estimatedGas.toStringAsFixed(4)} ETH'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(color: AppColors.border),
                  ),
                  _buildRow('Total Required', '${exception.totalRequired.toStringAsFixed(4)} ETH', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Balance Details
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  _buildRow('Current Balance', '${exception.currentBalance.toStringAsFixed(4)} ETH', color: AppColors.textPrimary),
                  const SizedBox(height: 8),
                  _buildRow('Missing Amount', '${exception.missingAmount.toStringAsFixed(4)} ETH', color: AppColors.danger, isBold: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // OK Button
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: const Text('Understood', style: AppTextStyles.labelLarge),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: (isBold ? AppTextStyles.subtitle1 : AppTextStyles.bodyMedium).copyWith(
              color: color ?? AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
