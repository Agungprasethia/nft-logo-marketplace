import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';

/// "Digital Artwork Agreement" popup dialog that must be approved
/// before the NFT minting process can proceed.
///
/// Use [AgreementDialog.show] to display the dialog.
/// Returns `true` if user agrees, `false` if cancelled.
class AgreementDialog extends StatefulWidget {
  const AgreementDialog({super.key});

  /// Show the agreement dialog. Returns true if user agrees.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const AgreementDialog(),
    );
    return result ?? false;
  }

  @override
  State<AgreementDialog> createState() => _AgreementDialogState();
}

class _AgreementDialogState extends State<AgreementDialog>
    with SingleTickerProviderStateMixin {
  bool _isAgreed = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

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
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // â”€â”€ Header â”€â”€
              _buildHeader(),

              // â”€â”€ Scrollable Body â”€â”€
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      _buildAgreementText(),
                      const SizedBox(height: AppSpacing.xl),
                      _buildCheckbox(),
                    ],
                  ),
                ),
              ),

              // â”€â”€ Buttons â”€â”€
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
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.frozenBlue.withValues(alpha: 0.1),
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
                  AppColors.primary.withValues(alpha: 0.3),
                  AppColors.frozenBlue.withValues(alpha: 0.3),
                ],
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.verified_user,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Digital Artwork Agreement',
            style: AppTextStyles.h2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Please read and agree to the following terms before proceeding with the NFT minting process',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementText() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Text(
        'By proceeding with the NFT minting process on this Blockchain-based Logo Marketplace platform, I hereby declare and agree that:\n\n'
        '(1) I am the original creator of the logo or digital artwork that I am uploading to this system.\n\n'
        '(2) The artwork I am uploading does not infringe upon any copyright, trademark, intellectual property rights, or any other legal rights of any third party.\n\n'
        '(3) I have full rights to mint this artwork as a Non-Fungible Token (NFT) and trade it through this marketplace system.\n\n'
        '(4) I understand that the artwork I upload must undergo an administrative validation and approval process by the platform\'s admin before it can proceed to the NFT minting stage.\n\n'
        '(5) I understand that once the NFT is minted, the metadata and ownership history will be permanently and immutably recorded on the Ethereum Virtual Machine (EVM) blockchain network.\n\n'
        '(6) I understand that the NFT minting process requires a transaction fee (gas fee) on the blockchain network, and this fee is non-refundable under any circumstances, including but not limited to cases where the NFT is rejected, not sold, or if I change my decision.\n\n'
        '(7) I confirm that the artwork I upload meets the platform\'s eligibility criteria, including but not limited to:\n'
        '      â€¢ It is an original work and not plagiarized\n'
        '      â€¢ It does not contain illegal, offensive, or inappropriate content\n'
        '      â€¢ It does not violate any intellectual property rights\n'
        '      â€¢ It has sufficient visual quality for marketplace display\n'
        '      â€¢ It does not contain unauthorized watermarks or third-party elements\n\n'
        '(8) I bear full legal responsibility for the authenticity and ownership of the artwork I upload.\n\n'
        '(9) I understand that this platform does not perform substantive verification of the authenticity of artworks and acts solely as a facilitator, and therefore is not liable for any violations committed by users.\n\n'
        'By agreeing to this statement, I consciously and voluntarily accept all legal and technical consequences arising from the NFT minting process for the artwork I upload.',
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildCheckbox() {
    return GestureDetector(
      onTap: () => setState(() => _isAgreed = !_isAgreed),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: _isAgreed
              ? AppColors.success.withValues(alpha: 0.1)
              : AppColors.accentOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _isAgreed
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.accentOrange.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _isAgreed,
                onChanged: (v) => setState(() => _isAgreed = v ?? false),
                activeColor: AppColors.success,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                side: BorderSide(
                  color: _isAgreed ? AppColors.success : AppColors.accentOrange,
                  width: 2,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'I declare that this artwork is my original creation and does not infringe upon the copyright of any other party.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: _isAgreed ? AppColors.success : AppColors.accentOrange,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, AppSpacing.xxl),
      child: Row(
        children: [
          // â”€â”€ Cancel Button â”€â”€
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
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

          // â”€â”€ Agree & Mint NFT Button â”€â”€
          Expanded(
            flex: 2,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                gradient: _isAgreed ? AppColors.primaryGradient : null,
                color: _isAgreed ? null : AppColors.surfaceLight,
              ),
              child: ElevatedButton(
                onPressed: _isAgreed
                    ? () => Navigator.of(context).pop(true)
                    : null,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified,
                      size: 18,
                      color: _isAgreed ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Agree & Mint NFT',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: _isAgreed ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
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

