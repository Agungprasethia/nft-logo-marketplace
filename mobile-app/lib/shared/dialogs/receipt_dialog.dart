import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:url_launcher/url_launcher.dart';

class ReceiptDialog extends StatelessWidget {
  final LogoNFT logo;
  final Auction? auction;
  final double myBid;
  final String status;
  final String currentWallet;

  const ReceiptDialog({
    super.key,
    required this.logo,
    required this.auction,
    required this.myBid,
    required this.status,
    required this.currentWallet,
  });

  static void show(
    BuildContext context, {
    required LogoNFT logo,
    Auction? auction,
    required double myBid,
    required String status,
    required String currentWallet,
  }) {
    showDialog(
      context: context,
      builder: (context) => ReceiptDialog(
        logo: logo,
        auction: auction,
        myBid: myBid,
        status: status,
        currentWallet: currentWallet,
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPaid = status == 'PAID/CLAIMED';
    final DateTime date = logo.paymentCompletedAt ?? logo.endTime ?? DateTime.now();
    final String dateString = DateFormat('MMM dd, yyyy · HH:mm').format(date);
    
    // Status text color mapping
    Color statusColor = Colors.white;
    if (status == 'WINNING') {
      statusColor = const Color(0xFF4ADE80);
    } else if (status == 'PAID/CLAIMED') {
      statusColor = const Color(0xFF93C5FD);
    } else if (status == 'OUTBID' || status == 'CANCELLED' || status == 'PAYMENT FAILED') {
      statusColor = const Color(0xFFF87171);
    } else if (status == 'LOST') {
      statusColor = const Color(0xFF6B7280);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF2A2A3F), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1A1A2E), width: 1)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Purchase Receipt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image & Basic Info
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: CachedNetworkImage(
                            imageUrl: logo.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: const Color(0xFF1A1A2E)),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1A1A2E),
                              child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              logo.name,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Token #${logo.tokenId}',
                              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Details Grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07070F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1A1A2E), width: 1),
                    ),
                    child: Column(
                      children: [
                        _buildReceiptRow('Status', status, valueColor: statusColor),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Color(0xFF1A1A2E), height: 1),
                        ),
                        _buildReceiptRow('Your Bid Amount', '$myBid ETH', valueColor: const Color(0xFFA78BFA)),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Color(0xFF1A1A2E), height: 1),
                        ),
                        _buildReceiptRow('Date', dateString),
                        if (isPaid && logo.txHash != null && logo.txHash!.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(color: Color(0xFF1A1A2E), height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Tx Hash', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                              Row(
                                children: [
                                  Text(
                                    _shortenAddress(logo.txHash!),
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: logo.txHash!));
                                      NotificationManager.show(
                                        context: context,
                                        title: 'Copied',
                                        message: 'Transaction hash copied to clipboard',
                                        type: NotificationType.success,
                                      );
                                    },
                                    child: const Icon(Icons.copy, color: Color(0xFF6B7280), size: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () async {
                                      final url = Uri.parse('https://sepolia.etherscan.io/tx/${logo.txHash}');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url, mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Icon(Icons.open_in_new, color: Color(0xFF3B82F6), size: 14),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Close Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED), // Accent purple
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
