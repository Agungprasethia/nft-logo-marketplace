import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/wallet_connect_modal.dart';

import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/profile_setup_page.dart';

class WalletUtils {
  static Future<bool> showConnectDialog(
    BuildContext context, 
    Web3ServiceBase web3Service, {
    String title = 'Connect Wallet',
    String message = 'Choose a wallet to connect to the marketplace.',
  }) async {
    // Delegate entirely to the new WalletConnectModal which handles the robust
    // polling and deep-link-free connection flow for all Android devices.
    final success = await WalletConnectModal.show(
      context,
      title: title,
      message: message,
    );

    if (success && web3Service.isConnected && context.mounted) {
      // Check if profile is complete
      try {
        final address = web3Service.currentAddress?.toLowerCase();
        final uid = AuthService.instance.currentUser?.uid ?? address;
        
        if (uid != null) {
          final userData = await AuthService.instance.getUserData(uid);
          
          final isComplete = userData?.isProfileComplete ?? false;
          if (!isComplete && context.mounted) {
            if (kDebugMode) { 
              debugPrint('[ONBOARDING] Profile incomplete or new user — redirecting to ProfileSetupPage'); 
            }
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) { debugPrint('Error checking profile after connect: $e'); }
      }
    }
    
    return success;
  }
}
