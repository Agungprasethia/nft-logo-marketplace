import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/widgets/wallet_connect_modal.dart';

class WalletUtils {
  static Future<void> showConnectDialog(BuildContext context, Web3ServiceBase web3Service) async {
    // Delegate entirely to the new WalletConnectModal which handles the robust
    // polling and deep-link-free connection flow for all Android devices.
    await WalletConnectModal.show(
      context,
      title: 'Connect Wallet',
      message: 'Choose a wallet to connect to the marketplace.',
    );
  }
}
