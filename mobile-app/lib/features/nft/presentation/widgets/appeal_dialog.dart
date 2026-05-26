import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

class AppealDialog extends StatefulWidget {
  final int tokenId;
  final String reportId;
  final String creatorWallet;
  final String? creatorUsername;

  const AppealDialog({
    super.key,
    required this.tokenId,
    required this.reportId,
    required this.creatorWallet,
    this.creatorUsername,
  });

  static Future<void> show(
    BuildContext context, {
    required int tokenId,
    required String reportId,
    required String creatorWallet,
    String? creatorUsername,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppealDialog(
        tokenId: tokenId,
        reportId: reportId,
        creatorWallet: creatorWallet,
        creatorUsername: creatorUsername,
      ),
    );
  }

  @override
  State<AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<AppealDialog> {
  final TextEditingController _messageController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitAppeal() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      NotificationManager.show(
        context: context,
        title: 'Validation Error',
        message: 'Please enter an appeal message',
        type: NotificationType.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirestoreService.instance.submitAppeal(
        widget.tokenId,
        widget.creatorWallet,
        widget.creatorUsername ?? '',
        message,
        widget.reportId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      NotificationManager.show(
        context: context,
        title: 'Appeal Submitted',
        message: 'Appeal submitted successfully. Awaiting moderator review.',
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Error',
        message: e.toString().replaceFirst('Exception: ', ''),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.gavel, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                const Expanded(
                  child: Text('Submit Appeal', style: AppTextStyles.h3),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Info
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppColors.accentOrange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Provide proof or explain why the report is incorrect. Your appeal will be reviewed by a moderator.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Text Field
            Text(
              'Your Defense / Proof',
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _messageController,
              maxLines: 5,
              maxLength: 500,
              enabled: !_isSubmitting,
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'e.g., "This logo is original work. I own the copyright. Here is my portfolio..."',
                hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.surfaceLight),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.surfaceLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                contentPadding: const EdgeInsets.all(AppSpacing.md),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.textSecondary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: Text('Cancel', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitAppeal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Submit Appeal', style: AppTextStyles.labelLarge),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
