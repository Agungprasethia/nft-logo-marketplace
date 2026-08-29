import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/walletconnect_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/profile_setup_page.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class WalletUtils {
  static Future<bool> showConnectDialog(
    BuildContext context, 
    Web3ServiceBase web3Service, {
    String title = 'Connect Wallet',
    String message = 'Choose a wallet to connect to the marketplace.',
  }) async {
    bool success = false;

    try {
      final wcs = WalletConnectService.instance;
      if (!wcs.isInitialized) {
        await wcs.initialize(context: context);
      }
      
      if (wcs.appKitModal != null) {
        // This unified UI handles both desktop extension detection (EIP-6963)
        // and mobile app deep-linking out of the box!
        await wcs.appKitModal!.openModalView();
        
        // Modal is closed. Check if connection was successful.
        success = web3Service.isConnected || wcs.isConnected;
      }
    } catch (e) {
      if (context.mounted) {
        NotificationManager.show(
          context: context,
          title: 'Connection Failed',
          message: e.toString().replaceFirst('Exception: ', ''),
          type: NotificationType.error,
        );
      }
      return false;
    }

    if (success && web3Service.isConnected && context.mounted) {
      // Check if profile is complete
      try {
        final address = web3Service.currentAddress?.toLowerCase();
        final uid = AuthService.instance.currentUser?.uid ?? address;
        
        if (uid != null) {
          final userData = await AuthService.instance.getUserData(uid.toLowerCase());
          
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
