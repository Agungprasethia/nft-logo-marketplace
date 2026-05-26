import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

class WalletConnectModal extends StatefulWidget {
  final String title;
  final String message;

  const WalletConnectModal({
    super.key,
    this.title = 'Connect Wallet Required',
    this.message = 'Please connect your wallet to participate in the marketplace.',
  });

  static bool _isDialogOpen = false;

  static Future<bool> show(BuildContext context, {
    String title = 'Connect Wallet Required',
    String message = 'Please connect your wallet to access this feature.',
  }) async {
    if (_isDialogOpen) return false;
    _isDialogOpen = true;

    try {
      final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Wallet Connect Modal',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return WalletConnectModal(title: title, message: message);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
      return result ?? false;
    } finally {
      _isDialogOpen = false;
    }
  }

  @override
  State<WalletConnectModal> createState() => _WalletConnectModalState();
}

class _WalletConnectModalState extends State<WalletConnectModal> {
  bool _isConnecting = false;

  Future<void> _handleConnect() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);

    try {
      await WalletUtils.showConnectDialog(context, Web3Service.instance);
      if (Web3Service.instance.isConnected) {
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Connection Failed',
        message: e.toString().replaceFirst("Exception: ", ""),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              AppShadows.soft.first,
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MetaMask Icon / Illustration
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  boxShadow: AppShadows.glowPrimary,
                ),
                child: Image.asset(
                  'assets/images/metamask_fox.png',
                  errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_wallet, size: 36, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 24),
              
              Text(
                widget.title,
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              
              Text(
                widget.message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Connect Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _handleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    elevation: 0,
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Connect Wallet',
                              style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Cancel Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Cancel', style: AppTextStyles.labelLarge),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
