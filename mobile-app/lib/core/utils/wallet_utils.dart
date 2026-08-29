import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/wallet_connect_modal.dart';

import 'package:flutter/foundation.dart';
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

    if (kIsWeb) {
      bool installed = web3Service.isMetaMaskInstalled;
      
      // Tunggu hingga 1.5 detik agar MetaMask sempat inject window.ethereum ke DOM
      // karena eksekusi di Flutter Web seringkali lebih cepat dari proses inject extension
      if (!installed) {
        for (int i = 0; i < 15; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (web3Service.isMetaMaskInstalled) {
            installed = true;
            break;
          }
        }
      }

      if (!web3Service.isMobileDevice) {
        // Desktop Web: Wajib pakai ekstensi MetaMask
        if (installed) {
          try {
            success = await web3Service.connectWallet();
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
        } else {
          if (context.mounted) {
            NotificationManager.show(
              context: context,
              title: 'MetaMask Required',
              message: 'Please install the MetaMask browser extension to connect.',
              type: NotificationType.warning,
            );
          }
          return false;
        }
      } else {
        // Mobile Web
        if (installed) {
          // Jika dibuka dari in-app browser MetaMask
          try {
            success = await web3Service.connectWallet();
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
        } else {
          // Jika dibuka dari Chrome/Safari di HP biasa -> pakai WalletConnectModal
          success = await WalletConnectModal.show(
            context,
            title: title,
            message: message,
          );
        }
      }
    } else {
      // Native Android/iOS: Selalu pakai WalletConnectModal
      success = await WalletConnectModal.show(
        context,
        title: title,
        message: message,
      );
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
