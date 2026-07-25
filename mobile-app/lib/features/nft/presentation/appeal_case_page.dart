import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/shared/models/appeal_case.dart';
import 'package:nft_logo_marketplace/shared/models/appeal_message.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';

class AppealCasePage extends StatefulWidget {
  final LogoNFT logo;

  const AppealCasePage({super.key, required this.logo});

  @override
  State<AppealCasePage> createState() => _AppealCasePageState();
}

class _AppealCasePageState extends State<AppealCasePage> {
  final _web3 = Web3Service.instance;
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage(String caseId, String role) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await FirestoreService.instance.sendAppealMessage(
        caseId: caseId,
        senderWallet: _web3.currentAddress ?? '',
        senderRole: role,
        message: text,
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Copyright Review Case', style: AppTextStyles.h3),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: StreamBuilder<AppealCase?>(
        stream: FirestoreService.instance.getAppealCaseStreamByToken(widget.logo.tokenId),
        builder: (context, caseSnapshot) {
          if (caseSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final appealCase = caseSnapshot.data;
          if (appealCase == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: AppSpacing.md),
                    Text('No active case found for this NFT.', style: AppTextStyles.bodyLarge),
                  ],
                ),
              ),
            );
          }

          final currentUserWallet = _web3.currentAddress?.toLowerCase() ?? '';
          final isReporter = appealCase.reporterWallet.toLowerCase() == currentUserWallet;
          final isOwner = appealCase.ownerWallet.toLowerCase() == currentUserWallet;
          final isAdmin = currentUserWallet == 'admin_wallet_here'; // Simplification for now, we usually check claims or fixed address
          // Normally admins have a separate dashboard, but if we need a quick mock:
          final role = isReporter ? 'reporter' : (isOwner ? 'owner' : (isAdmin ? 'admin' : 'viewer'));
          final canReply = isReporter || isOwner || isAdmin;

          return Column(
            children: [
              // Info Banner
              Container(
                margin: const EdgeInsets.all(AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.gavel, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Case #${appealCase.caseId.substring(0, 8).toUpperCase()}', style: AppTextStyles.labelLarge),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: appealCase.status == 'open' ? Colors.lightBlue.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            appealCase.status.toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: appealCase.status == 'open' ? Colors.lightBlue : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text('NFT: ${widget.logo.name} (#${widget.logo.tokenId})', style: AppTextStyles.bodyMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Reporter: ${_shortenWallet(appealCase.reporterWallet)}', style: AppTextStyles.bodySmall),
                    Text('Owner: ${_shortenWallet(appealCase.ownerWallet)}', style: AppTextStyles.bodySmall),
                  ],
                ),
              ),

              // Messages List
              Expanded(
                child: StreamBuilder<List<AppealMessage>>(
                  stream: FirestoreService.instance.getAppealMessagesStream(appealCase.caseId),
                  builder: (context, msgSnapshot) {
                    if (msgSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final messages = msgSnapshot.data ?? [];
                    if (messages.isEmpty) {
                      return Center(
                        child: Text('No messages yet.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      );
                    }
                    return RefreshIndicator(
      onRefresh: () async { setState(() {}); },
      child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      reverse: true, // Newest at bottom visually
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderWallet.toLowerCase() == currentUserWallet;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.lg).copyWith(
                                bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(AppRadius.lg),
                                bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(AppRadius.lg),
                              ),
                              border: Border.all(color: isMe ? AppColors.primary.withValues(alpha: 0.3) : AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isMe ? 'You' : msg.senderRole.toUpperCase(),
                                      style: AppTextStyles.labelSmall.copyWith(
                                        color: isMe ? AppColors.primary : AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (!isMe) ...[
                                      const SizedBox(width: 6),
                                      Text(_shortenWallet(msg.senderWallet), style: AppTextStyles.caption),
                                    ]
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(msg.message, style: AppTextStyles.bodyMedium),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
                  },
                ),
              ),

              // Input Area
              if (canReply && appealCase.status == 'open')
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              borderSide: const BorderSide(color: AppColors.primary),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: () => _sendMessage(appealCase.caseId, role),
                        ),
                      ),
                    ],
                  ),
                ),
                
              if (!canReply && appealCase.status == 'open')
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  color: AppColors.surface,
                  child: Text(
                    'Only the owner, reporter, and admins can reply to this case.',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _shortenWallet(String wallet) {
    if (wallet.length < 10) return wallet;
    return '${wallet.substring(0, 6)}...${wallet.substring(wallet.length - 4)}';
  }
}
