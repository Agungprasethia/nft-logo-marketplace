import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';
import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/widgets/auction_step_indicator.dart';

class AuctionPaymentPage extends StatefulWidget {
  final int tokenId;

  const AuctionPaymentPage({super.key, required this.tokenId});

  @override
  State<AuctionPaymentPage> createState() => _AuctionPaymentPageState();
}

class _AuctionPaymentPageState extends State<AuctionPaymentPage> {
  final _web3 = Web3Service.instance;
  bool _isProcessingPayment = false;

  Future<LogoNFT?> _fetchLogo(int tokenId) async {
    try {
      final data = await FirestoreService.instance.getNFTData(tokenId);
      if (data != null) {
        return LogoNFT.fromFirestore(data);
      }
    } catch (e) {
      debugPrint('Error fetching logo: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Payment', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: FutureBuilder<LogoNFT?>(
        future: _fetchLogo(widget.tokenId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CustomLoadingIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Failed to load NFT details.', style: TextStyle(color: AppColors.danger)));
          }

          final logo = snapshot.data!;
          return FutureBuilder<Auction?>(
            future: FirestoreService.instance.getAuction(widget.tokenId),
            builder: (context, auctionSnapshot) {
              if (auctionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CustomLoadingIndicator());
              }
              final auction = auctionSnapshot.data;
              if (auction == null) {
                return const Center(child: Text('Auction not found.', style: TextStyle(color: AppColors.danger)));
              }

              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AuctionStepIndicator(currentStep: 2),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFFBE6), Color(0xFFFFF1B8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.2),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Text('🎉', style: TextStyle(fontSize: 40)),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('You won this auction!', style: AppTextStyles.h3.copyWith(color: Colors.orange[800])),
                                    const SizedBox(height: 4),
                                    Text(
                                      'To claim your NFT, complete the blockchain payment below.',
                                      style: AppTextStyles.bodyMedium.copyWith(color: Colors.orange[900]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildHeroPreview(logo),
                        const SizedBox(height: AppSpacing.xl),
                        _buildPaymentSummary(logo, auction),
                        const SizedBox(height: AppSpacing.xl),
                        _buildStrictWarning(),
                        const SizedBox(height: 100), // Space for bottom button
                      ],
                    ),
                  ),
                  _buildStickyBottomButton(logo, auction),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildHeroPreview(LogoNFT logo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          height: 350,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 40,
                spreadRadius: -10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: CachedNetworkImage(
              imageUrl: logo.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(child: CustomLoadingIndicator(size: 32)),
              errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 50, color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          logo.name,
          style: AppTextStyles.h2.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Token #${logo.tokenId}',
          style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Description', style: AppTextStyles.labelMedium),
        const SizedBox(height: 4),
        Text(
          logo.description,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Creator', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                  Text(
                    logo.creatorUsername ?? logo.creatorShort,
                    style: AppTextStyles.labelLarge,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSummary(LogoNFT logo, Auction auction) {
    final double serviceFee = auction.highestBid * (Web3ServiceBase.platformFeePercentage / 100);
    final double totalPayment = auction.highestBid; // Service fee is deducted from seller, buyer pays exact bid

    debugPrint('🔥 [PAYMENT PAGE DEBUG] TokenID: ${logo.tokenId} | logo.highestBid: ${logo.highestBid} | auction.highestBid: ${auction.highestBid}');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Summary', style: AppTextStyles.h3),
          const SizedBox(height: AppSpacing.lg),
          _buildSummaryRow('Your Winning Bid', '${auction.highestBid.toStringAsFixed(4)} ETH', valueColor: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow('Network', 'Sepolia'),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow('Service Fee (2.5%)', '${serviceFee.toStringAsFixed(4)} ETH', subtitle: 'Deducted from creator'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(color: AppColors.border),
          ),
          _buildSummaryRow('Total Payment', '${totalPayment.toStringAsFixed(4)} ETH', valueColor: AppColors.primary, isBold: true),
          const SizedBox(height: AppSpacing.sm),
          _buildSummaryRow('Gas Fee', 'estimated by MetaMask', valueColor: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor, String? subtitle, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              if (subtitle != null)
                Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.6))),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: AppTextStyles.labelLarge.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            fontSize: isBold ? 18 : null,
          ),
        ),
      ],
    );
  }

  Widget _buildStrictWarning() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.accentOrange),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Important', style: AppTextStyles.labelLarge.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'You must complete the EXACT blockchain payment to claim ownership.',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyBottomButton(LogoNFT logo, Auction auction) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BLOCKCHAIN PAYMENT REQUIRED BADGE
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock, size: 14, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        'BLOCKCHAIN PAYMENT',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· MetaMask needed',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.amber.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (logo.paymentDeadline != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AuctionPaymentCountdown(
                  deadline: logo.paymentDeadline!,
                  onExpired: () {
                    if (mounted) setState(() {});
                  },
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: (_isProcessingPayment || (logo.paymentDeadline != null && DateTime.now().isAfter(logo.paymentDeadline!)))
                    ? null
                    : () => _processPayment(logo, auction),
                icon: _isProcessingPayment
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(
                  _isProcessingPayment ? 'Processing...' : 'Pay Now',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'MetaMask will open to confirm the transaction',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPayment(LogoNFT logo, Auction auction) async {
    if (_web3.chainId != Web3ServiceBase.sepoliaChainId) {
      NotificationManager.show(
        context: context,
        title: 'Wrong Network',
        message: 'Please switch your wallet to Sepolia Testnet to complete the payment.',
        type: NotificationType.error,
      );
      return;
    }

    setState(() => _isProcessingPayment = true);

    // Show Processing Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: AppSpacing.md),
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: AppSpacing.xl),
                Text('Waiting for blockchain confirmation...', style: AppTextStyles.h3, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Please confirm the transaction in MetaMask and wait for blockchain confirmation. This may take a few moments.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );

    try {
      final txHash = await _web3.payAuctionWinner(logo.creatorWallet, auction.highestBid);

      await FirestoreService.instance.completePayment(
        logo.tokenId,
        _web3.currentAddress!,
        _web3.balance,
        txHash: txHash,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog

      // Show Success Dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 28),
              SizedBox(width: 12),
              Text('Payment Successful!', style: TextStyle(color: AppColors.textPrimary)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ownership Successfully Transferred. The NFT is now in your collection.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Transaction Hash:', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(txHash, style: const TextStyle(color: AppColors.primary, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close payment page (return to profile)
              },
              child: const Text('Go to Collection', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog
      NotificationManager.show(
        context: context,
        title: 'Payment Failed',
        message: e.toString().replaceAll('Exception: ', ''),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }
}

class AuctionPaymentCountdown extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback? onExpired;

  const AuctionPaymentCountdown({super.key, required this.deadline, this.onExpired});

  @override
  State<AuctionPaymentCountdown> createState() => _AuctionPaymentCountdownState();
}

class _AuctionPaymentCountdownState extends State<AuctionPaymentCountdown> with SingleTickerProviderStateMixin {
  late Timer _timer;
  late ValueNotifier<Duration> _remaining;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _hasExpiredFired = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _remaining = ValueNotifier(widget.deadline.difference(now));
    if (_remaining.value.isNegative) _remaining.value = Duration.zero;
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final diff = widget.deadline.difference(DateTime.now());
      if (diff.isNegative) {
        _remaining.value = Duration.zero;
        _timer.cancel();
        if (!_hasExpiredFired) {
          _hasExpiredFired = true;
          widget.onExpired?.call();
        }
      } else {
        _remaining.value = diff;
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    _remaining.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _remaining,
      builder: (context, remaining, child) {
        if (remaining == Duration.zero) {
          _pulseController.stop();
          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.danger),
                const SizedBox(width: AppSpacing.sm),
                Text('PAYMENT EXPIRED\nThe winner failed to complete payment within 24 hours.',
                    style: AppTextStyles.labelMedium.copyWith(color: AppColors.danger, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ],
            ),
          );
        }

        Color color;
        bool shouldPulse = false;
        
        if (remaining.inHours >= 6) {
          color = AppColors.primary;
          _pulseController.stop();
        } else if (remaining.inHours >= 1) {
          color = AppColors.accentOrange;
          _pulseController.stop();
        } else {
          color = AppColors.danger;
          shouldPulse = true;
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
        }

        final hours = remaining.inHours.toString().padLeft(2, '0');
        final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
        final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
        final timeStr = '$hours:$minutes:$seconds';

        Widget countdownText = Text(
          'PAYMENT DEADLINE\n$timeStr',
          textAlign: TextAlign.center,
          style: AppTextStyles.labelLarge.copyWith(color: color, fontWeight: FontWeight.bold),
        );

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (shouldPulse)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Icon(Icons.timer, color: color, size: 20),
                  ),
                )
              else
                Icon(Icons.timer, color: color, size: 20),
              const SizedBox(width: AppSpacing.md),
              countdownText,
            ],
          ),
        );
      },
    );
  }
}
