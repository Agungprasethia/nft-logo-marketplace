import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

class WalletUtils {
  static Future<void> showConnectDialog(BuildContext context, Web3ServiceBase web3Service) async {
    final wallet = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect Wallet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your preferred wallet provider',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 24),
              _WalletOption(
                name: 'MetaMask',
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.orange,
                onTap: () => Navigator.pop(context, 'metamask'),
              ),
              _WalletOption(
                name: 'Trust Wallet',
                icon: Icons.security,
                color: Colors.blue,
                onTap: () => Navigator.pop(context, 'trust'),
              ),
              _WalletOption(
                name: 'Rainbow',
                icon: Icons.palette,
                color: Colors.purple,
                onTap: () => Navigator.pop(context, 'rainbow'),
              ),
              const Divider(),
              _WalletOption(
                name: 'Other Wallets',
                icon: Icons.more_horiz,
                color: Colors.grey.shade700,
                onTap: () => Navigator.pop(context, 'other'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (wallet != null) {
       try {
         await web3Service.connectWallet(walletName: wallet);
       } catch (e) {
         if (e.toString().contains('MetaMask is not installed')) {
           if (!context.mounted) return;
           _showInstallMetaMaskDialog(context);
         } else {
           rethrow;
         }
       }
    }
  }

  static void _showInstallMetaMaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.extension, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
            Text('MetaMask Required', style: AppTextStyles.h3),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MetaMask browser extension is not installed or not detected.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'To interact with this Web3 Marketplace, please install the MetaMask extension for your browser.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              launchUrl(Uri.parse('https://metamask.io/download/'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Install MetaMask'),
          ),
        ],
      ),
    );
  }
}

class _WalletOption extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _WalletOption({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }
}
