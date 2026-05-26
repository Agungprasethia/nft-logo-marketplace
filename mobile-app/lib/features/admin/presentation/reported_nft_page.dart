import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/utils/firestore_error_handler.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nft_logo_marketplace/features/auction/presentation/auction_page.dart';
import 'package:nft_logo_marketplace/features/profile/presentation/widgets/leaderboard_modal.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

class ReportedNftPage extends StatefulWidget {
  const ReportedNftPage({super.key});

  @override
  State<ReportedNftPage> createState() => _ReportedNftPageState();
}

class _ReportedNftPageState extends State<ReportedNftPage> {
  final String currentAdminId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_admin';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.getPendingReportsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        if (snapshot.hasError) {
          return FirestoreErrorHandler.buildErrorWidget(
            snapshot.error,
            onRetry: () {
              if (context is Element) {
                context.markNeedsBuild();
              }
            },
          );
        }

        final reportedList = snapshot.data ?? [];

        if (reportedList.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 48, color: AppColors.success),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('No pending reports', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.sm),
                Text('All clear! The marketplace is safe.', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: reportedList.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: _buildReportedNFTCard(context, reportedList[index]),
            );
          },
        );
      }
    );
  }

  Widget _buildReportedNFTCard(BuildContext context, Map<String, dynamic> reportData) {
    final tokenId = reportData['tokenId'] as int;
    final reportId = reportData['reportId'] as String;
    final nftTitle = reportData['nftTitle'] as String? ?? 'Token #$tokenId';
    final nftImageUrl = reportData['nftImageUrl'] as String? ?? '';
    final reason = reportData['reason'] as String? ?? 'No reason provided';
    final additionalNote = reportData['additionalNote'] as String? ?? '';
    final creatorWallet = reportData['creatorWallet'] as String? ?? '';
    final creatorUsername = reportData['creatorUsername'] as String? ?? '';
    final reporterWallet = reportData['reporterWallet'] as String? ?? '';
    final reporterUsername = reportData['reporterUsername'] as String? ?? '';
    final auctionStatusSnapshot = reportData['auctionStatusSnapshot'] as String? ?? 'Unknown';
    final snapshotHighestBid = (reportData['snapshotHighestBid'] as num?)?.toDouble() ?? 0.0;
    final snapshotTotalBids = reportData['snapshotTotalBids'] as int? ?? 0;
    final reportStatus = reportData['status'] as String? ?? 'pending';

    // Get live auction data if available
    double highestBid = snapshotHighestBid;
    int totalBids = snapshotTotalBids;
    AuctionStatus liveAuctionStatus = Auction.statusFromString(auctionStatusSnapshot);
    bool isLive = false;
    try {
      final auction = Web3Service.instance.allAuctions.firstWhere((a) => a.tokenId == tokenId);
      highestBid = auction.highestBid > 0 ? auction.highestBid : auction.startingPrice;
      totalBids = auction.totalBids;
      liveAuctionStatus = auction.status;
      isLive = auction.isOngoing;
    } catch (_) {}

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withValues(alpha: 0.05),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image + Title Row
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Thumbnail
                SizedBox(
                  width: 120,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E1024), Color(0xFF120A16)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: nftImageUrl.isNotEmpty
                        ? Image.network(nftImageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.danger),
                            ))
                        : const Center(
                            child: Icon(Icons.warning_amber_rounded, size: 40, color: AppColors.danger),
                          ),
                  ),
                ),
                // Title + Status
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          nftTitle,
                          style: AppTextStyles.h3,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.flag, size: 12, color: AppColors.danger),
                                  const SizedBox(width: 4),
                                  Text('REPORTED', style: AppTextStyles.labelSmall.copyWith(color: AppColors.danger, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            if (reportStatus == 'frozen') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.ac_unit, size: 12, color: AppColors.accentOrange),
                                    const SizedBox(width: 4),
                                    Text('FROZEN', style: AppTextStyles.labelSmall.copyWith(color: AppColors.accentOrange, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Text('Token #$tokenId', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Report reason
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.report_problem, size: 16, color: AppColors.accentOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Report Reason', style: AppTextStyles.labelSmall.copyWith(color: AppColors.accentOrange)),
                            const SizedBox(height: 2),
                            Text(reason, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (additionalNote.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('"$additionalNote"', style: AppTextStyles.bodySmall.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Creator Appeal FutureBuilder
                FutureBuilder<Map<String, dynamic>?>(
                  future: FirestoreService.instance.getAppealForReport(reportId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == null) {
                      return const SizedBox.shrink();
                    }
                    
                    final appealData = snapshot.data!;
                    final appealMsg = appealData['appealMessage'] ?? '';

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.gavel, size: 16, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text('Creator Appeal', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('"$appealMsg"', style: AppTextStyles.bodyMedium.copyWith(fontStyle: FontStyle.italic)),
                        ],
                      ),
                    );
                  },
                ),

                // Creator & Reporter info
                Row(
                  children: [
                    Expanded(
                      child: _buildPersonInfo(Icons.brush, 'Creator', creatorUsername, creatorWallet),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _buildPersonInfo(Icons.person, 'Reporter', reporterUsername, reporterWallet),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Auction Stats Row
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(Icons.gavel, '${highestBid.toStringAsFixed(4)} ETH', 'Highest Bid'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildStatChip(Icons.how_to_vote, '$totalBids', 'Total Bids'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildStatChip(Icons.info_outline, auctionStatusSnapshot.toUpperCase(), 'Status'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Action Buttons
                // Row 1: View Actions
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.visibility,
                        label: 'View NFT',
                        color: AppColors.surfaceLight,
                        textColor: AppColors.textPrimary,
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionPage(tokenId: tokenId))),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.leaderboard,
                        label: 'Leaderboard',
                        color: AppColors.primary.withValues(alpha: 0.15),
                        textColor: AppColors.primary,
                        onPressed: () => LeaderboardModal.show(context, tokenId: tokenId, status: liveAuctionStatus, isLive: isLive),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                // Row 2: Admin Actions
                if (reportStatus == 'pending')
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.ac_unit,
                          label: 'Freeze',
                          color: AppColors.danger,
                          textColor: AppColors.textPrimary,
                          onPressed: () => _handleFreezeAction(tokenId, reportId),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.check_circle_outline,
                          label: 'Dismiss',
                          color: AppColors.surfaceLight,
                          textColor: AppColors.textPrimary,
                          onPressed: () => _handleDismissAction(reportId),
                        ),
                      ),
                    ],
                  )
                else if (reportStatus == 'frozen')
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.restore,
                          label: 'Reopen',
                          color: AppColors.success,
                          textColor: AppColors.textPrimary,
                          onPressed: () => _handleReopenAction(tokenId, reportId),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.block,
                          label: 'Reject (Lock)',
                          color: AppColors.danger,
                          textColor: AppColors.textPrimary,
                          onPressed: () => _handleRejectAction(tokenId, reportId),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonInfo(IconData icon, String label, String username, String wallet) {
    final display = username.isNotEmpty ? username : _shortenAddress(wallet);
    final subtitle = username.isNotEmpty ? _shortenAddress(wallet) : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, fontSize: 9)),
                Text(display, style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.labelSmall.copyWith(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color textColor,
    Color? borderColor,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: FittedBox(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: borderColor != null ? BorderSide(color: borderColor, width: 1.5) : BorderSide.none,
        ),
        elevation: 0,
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  Future<void> _handleFreezeAction(int tokenId, String reportId) async {
    final confirmed = await _showConfirmDialog(
      'Freeze Auction', 
      'Freeze this auction for investigation? The countdown timer will pause and bidding will be temporarily disabled.',
      AppColors.danger,
    );
    if (!confirmed) return;

    try {
      await FirestoreService.instance.freezeReportedAuction(tokenId, currentAdminId, reportId);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'Auction Frozen!', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
    }
  }

  Future<void> _handleDismissAction(String reportId) async {
    final confirmed = await _showConfirmDialog(
      'Dismiss Report', 
      'Dismiss this report? No action will be taken against the NFT.',
      AppColors.textSecondary,
    );
    if (!confirmed) return;

    try {
      await FirestoreService.instance.dismissReport(reportId, currentAdminId);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'Report Dismissed!', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
    }
  }

  Future<void> _handleReopenAction(int tokenId, String reportId) async {
    final confirmed = await _showConfirmDialog(
      'Reopen Auction', 
      'Reopen this frozen auction? The countdown timer will resume and bidding will be enabled again.',
      AppColors.success,
    );
    if (!confirmed) return;

    try {
      await FirestoreService.instance.reopenAuction(tokenId, currentAdminId, reportId);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'Auction Reopened!', type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
    }
  }

  Future<void> _handleRejectAction(int tokenId, String reportId) async {
    final confirmed = await _showConfirmDialog(
      'Reject & Lock NFT', 
      'Permanently reject this NFT? It will be removed from all public listings, the auction will be cancelled, and all bids will be invalidated. This action is IRREVERSIBLE.',
      AppColors.danger,
    );
    if (!confirmed) return;

    try {
      await FirestoreService.instance.rejectAuction(tokenId, currentAdminId, reportId);
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Success', message: 'NFT Permanently Rejected!', type: NotificationType.error);
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(context: context, title: 'Error', message: e.toString().replaceFirst("Exception: ", ""), type: NotificationType.error);
    }
  }

  Future<bool> _showConfirmDialog(String title, String content, Color confirmColor) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text(title, style: AppTextStyles.h3),
        content: Text(content, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: AppColors.textPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }
}
