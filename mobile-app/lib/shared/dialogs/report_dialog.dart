import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

/// "Report Artwork" dialog with Web3-styled UI.
/// Requires connected wallet. Validates input and prevents duplicate reports.
class ReportDialog extends StatefulWidget {
  final int tokenId;

  const ReportDialog({super.key, required this.tokenId});

  /// Show the report dialog. Returns true if report was submitted.
  static Future<bool> show(BuildContext context, int tokenId) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => ReportDialog(tokenId: tokenId),
    );
    return result ?? false;
  }

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog>
    with SingleTickerProviderStateMixin {
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedReason;
  bool _isSubmitting = false;
  
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  final List<String> _reportReasons = [
    'Copyright infringement',
    'Stolen logo',
    'Offensive content',
    'Fake identity',
    'Spam',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      _showSnackBar('Please select a reason', AppColors.danger);
      return;
    }

    final web3 = Web3Service.instance;
    if (!web3.isConnected || web3.currentAddress == null) {
      _showSnackBar('Please connect your wallet first', AppColors.danger);
      return;
    }

    final reporterWallet = web3.currentAddress!;
    
    // Fetch NFT Data
    final logo = web3.allLogos.firstWhere(
      (l) => l.tokenId == widget.tokenId,
      orElse: () => throw Exception('NFT not found locally'),
    );

    if (logo.isFrozen) {
      _showSnackBar('This NFT is already frozen and under investigation.', AppColors.accentOrange);
      return;
    }

    if (logo.creator.toLowerCase() == reporterWallet.toLowerCase() ||
        logo.ownerWallet.toLowerCase() == reporterWallet.toLowerCase()) {
      _showSnackBar('You cannot report your own NFT.', AppColors.danger);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Get Reporter Username
      String reporterUsername = 'Unknown';
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final profile = await AuthService.instance.getUserData(firebaseUser.uid);
        if (profile != null) {
           reporterUsername = profile.username ?? profile.fullName;
        }
      }

      await FirestoreService.instance.submitNFTReport(
        tokenId: widget.tokenId,
        reporterWallet: reporterWallet,
        reporterUsername: reporterUsername,
        creatorWallet: logo.creator,
        creatorUsername: logo.creatorUsername ?? '',
        nftTitle: logo.name,
        nftImageUrl: logo.imageUrl,
        reason: _selectedReason!,
        additionalNote: _noteController.text.trim(),
      );

      if (!mounted) return;
      _showSnackBar('Report submitted successfully. Thank you!', AppColors.success);

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(e.toString().replaceFirst('Exception: ', ''), AppColors.accentOrange);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    NotificationType type = NotificationType.info;
    if (color == AppColors.success) {
      type = NotificationType.success;
    } else if (color == AppColors.danger) {
      type = NotificationType.error;
    } else if (color == AppColors.accentOrange) {
      type = NotificationType.warning;
    }

    NotificationManager.show(
      context: context,
      title: 'Report Update',
      message: message,
      type: type,
      saveToHistory: false, // Prevents duplicate history entries
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: AppColors.danger.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      _buildFormInputs(),
                      const SizedBox(height: AppSpacing.sm),
                      _buildGuidelines(),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.danger.withValues(alpha: 0.15),
            AppColors.accentOrange.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.danger.withValues(alpha: 0.3),
                  AppColors.accentOrange.withValues(alpha: 0.3),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.flag_rounded,
              size: 32,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Report Artwork',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Help us maintain a safe marketplace by reporting inappropriate or infringing content',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFormInputs() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reason', style: AppTextStyles.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _selectedReason,
            hint: Text('Select a reason', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            items: _reportReasons.map((r) => DropdownMenuItem(value: r, child: Text(r, style: AppTextStyles.bodyMedium))).toList(),
            onChanged: (val) => setState(() => _selectedReason = val),
            dropdownColor: AppColors.surfaceLight,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
              ),
            ),
            validator: (v) => v == null ? 'Please select a reason' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          
          Text('Additional Notes (Optional)', style: AppTextStyles.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _noteController,
            maxLines: 3,
            maxLength: 300,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Provide any additional details...',
              hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surfaceLight,
              counterStyle: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelines() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.accentOrange),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Reports are reviewed to ensure marketplace integrity. '
              'False reports may result in restrictions.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.accentOrange,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, AppSpacing.xxl),
      child: Row(
        children: [
          // Cancel Button
          Expanded(
            child: OutlinedButton(
              onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: const Text(
                'Cancel',
                style: AppTextStyles.labelMedium,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Submit Report Button
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                gradient: const LinearGradient(
                  colors: [AppColors.danger, AppColors.accentOrange],
                ),
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flag_rounded, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Text(
                            'Submit Report',
                            style: AppTextStyles.labelLarge,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

