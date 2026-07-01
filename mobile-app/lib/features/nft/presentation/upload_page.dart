import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';


import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:nft_logo_marketplace/core/services/notification_service.dart';
import 'package:nft_logo_marketplace/core/services/pinata_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:nft_logo_marketplace/shared/dialogs/agreement_dialog.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';

class UploadPage extends StatefulWidget {
  final VoidCallback? onMintSuccess;

  const UploadPage({super.key, this.onMintSuccess});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController(text: '0.01');
  final _web3 = Web3Service.instance;
  final _picker = ImagePicker();

  String? _imageBase64;
  Uint8List? _imageBytes;
  bool _isLoading = false;
  bool _isContractReady = false;
  bool _isInitializingContract = false;
  String _statusMessage = '';
  String _selectedCategory = NFTCategory.technology;
  int _auctionDurationMinutes = 5;

  @override
  void initState() {
    super.initState();
    _web3.addListener(_refresh);
    _ensureWeb3Ready();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _web3.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Ensure Web3 contracts are initialized before allowing mint
  Future<void> _ensureWeb3Ready() async {
    if (_isContractReady) return;

    setState(() => _isInitializingContract = true);

    try {
      if (kDebugMode) { debugPrint('[WEB3] UploadPage: ensuring Web3 readiness...'); }
      await _web3.initialize();

      // Check contract readiness (mobile exposes isContractReady)
      final isReady = _web3.isInitialized && _web3.isConnected;
      if (kDebugMode) { debugPrint('[WEB3] UploadPage: initialized=${_web3.isInitialized}, connected=${_web3.isConnected}'); }

      if (mounted) {
        setState(() {
          _isContractReady = isReady || _web3.isInitialized;
          _isInitializingContract = false;
        });
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('[WEB3] UploadPage: Web3 readiness check failed: $e'); }
      if (mounted) {
        setState(() => _isInitializingContract = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final base64 = 'data:image/png;base64,${base64Encode(bytes)}';

      setState(() {
        _imageBytes = bytes;
        _imageBase64 = base64;
      });
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Error',
        message: 'Error picking image: $e',
        type: NotificationType.error,
      );
    }
  }

  bool _isMinting = false;
  bool _isProcessing = false;

  Future<void> _submitForReview() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageBase64 == null) {
      NotificationManager.show(
        context: context,
        title: 'Validation Error',
        message: 'Please select an artwork image first',
        type: NotificationType.error,
      );
      return;
    }

    // Show Digital Artwork Agreement popup FIRST â€” mint is locked until agreed
    final agreed = await AgreementDialog.show(context);
    if (!agreed || !mounted) return;

    if (!_web3.isConnected) {
      NotificationManager.show(
        context: context,
        title: 'Wallet Required',
        message: 'Please connect your wallet first',
        type: NotificationType.warning,
      );
      return;
    }

    if (!_web3.isOnSepolia) {
      NotificationManager.show(
        context: context,
        title: 'Wrong Network',
        message: 'Please switch your wallet to Sepolia Testnet',
        type: NotificationType.error,
      );
      return;
    }

    // Ensure contract is initialized before minting
    if (!_isContractReady || _isInitializingContract) {
      setState(() => _isInitializingContract = true);
      await _ensureWeb3Ready();
      if (!_isContractReady) {
        if (!mounted) return;
        NotificationManager.show(
          context: context,
          title: 'Contract Not Ready',
          message: 'Smart contract is still initializing. Please wait a moment and try again.',
          type: NotificationType.warning,
        );
        return;
      }
    }

    // --- Anti-Spam Protection ---
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final lastMint = userDoc.data()?['lastMintTime'] as Timestamp?;
          if (lastMint != null) {
            final diff = DateTime.now().difference(lastMint.toDate());
            if (diff.inSeconds < 30) {
              if (!mounted) return;
              NotificationManager.show(
                context: context,
                title: 'Rate Limit',
                message: 'Please wait 30 seconds before minting again (Anti-spam protection)',
                type: NotificationType.error,
              );
              return;
            }
          }
        }
      } catch (e) {
        if (kDebugMode) { debugPrint('Error checking anti-spam: $e'); }
      }
    }
    // ----------------------------

    setState(() {
      _isLoading = true;
      _isMinting = true;
      _isProcessing = true;
      _statusMessage = 'Uploading Image to IPFS... 1/4\nSaving logo to Pinata';
    });

    try {
      // â•â•â• STEP 1: Upload image to Pinata IPFS â•â•â•
      if (kDebugMode) { debugPrint('[UPLOAD START] Uploading image to IPFS...'); }
      final ipfsImageUrl = await PinataService.uploadImage(
        _imageBytes!, 
        'nft_logo_${DateTime.now().millisecondsSinceEpoch}.png'
      );
      
      if (!mounted) return;
      if (kDebugMode) { debugPrint('[IPFS IMAGE SUCCESS] âœ… Image uploaded: $ipfsImageUrl'); }

      setState(() {
        _statusMessage = 'Uploading Metadata to IPFS... 2/4\nSaving NFT metadata JSON';
      });

      // â•â•â• STEP 2: Upload NFT metadata JSON to Pinata IPFS â•â•â•
      if (kDebugMode) { debugPrint('[UPLOAD START] Uploading metadata to IPFS...'); }
      final ipfsMetadataUrl = await PinataService.uploadMetadata(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        imageIpfsUrl: ipfsImageUrl,
        category: _selectedCategory,
      );
      
      if (!mounted) return;
      if (kDebugMode) { debugPrint('[IPFS METADATA SUCCESS] âœ… Metadata uploaded: $ipfsMetadataUrl'); }

      final copyrightHash = sha256.convert(_imageBytes!).toString();

      setState(() {
        _statusMessage = 'Minting on Blockchain... 3/4\nConfirm in MetaMask';
      });

      // â•â•â• STEP 3: BLOCKCHAIN MINT â€” ATOMIC â•â•â•
      // mintLogo() handles:
      //   - Send transaction to smart contract
      //   - Wait for blockchain receipt
      //   - Parse REAL tokenId from receipt
      //   - Build LogoNFT with REAL tokenId
      //   - Save to Firestore ONLY after blockchain success
      //   - Return the REAL LogoNFT
      if (kDebugMode) { debugPrint('[MINT START] Calling mintLogo()...'); }
      
      final mintedNFT = await _web3.mintLogo(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        imageUrl: ipfsImageUrl,
        price: double.parse(_priceController.text),
        category: _selectedCategory,
        metadataUrl: ipfsMetadataUrl,
        copyrightHash: copyrightHash,
        hashAlgorithm: 'SHA-256',
      );

      // Save auction duration to Firestore for Quick Auction Mode
      try {
        await FirebaseFirestore.instance.collection('nfts').doc(mintedNFT.tokenId.toString()).set({
          'auctionDurationMinutes': _auctionDurationMinutes,
          'auctionDuration': _auctionDurationMinutes * 60,
        }, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) { debugPrint('Failed to update auction duration in Firestore: $e'); }
      }

      if (!mounted) return;
      if (kDebugMode) { debugPrint('[MINT COMPLETE] âœ… NFT minted with REAL tokenId: ${mintedNFT.tokenId}'); }
      if (kDebugMode) { debugPrint('[MINT COMPLETE] ✅ NFT minted with REAL tokenId: ${mintedNFT.tokenId}'); }

      setState(() {
        _statusMessage = 'Finalizing... 4/4';
      });

      // ═══ STEP 4: SUCCESS — Reload data & show UI ═══
      _web3.loadFromChain();

      if (mintedNFT.txHash != null && mintedNFT.txHash!.isNotEmpty) {
        NotificationManager.show(
          context: context,
          title: 'Transaction Confirmed',
          message: 'Mint transaction confirmed on blockchain. Hash: ${mintedNFT.txHash!.length >= 10 ? mintedNFT.txHash!.substring(0, 10) : mintedNFT.txHash}...',
          type: NotificationType.web3,
        );
      }

      // Show success dialog with IPFS info
      _showSuccessDialog(
        mintedNFT.name,
        ipfsImageUrl: ipfsImageUrl,
        ipfsMetadataUrl: ipfsMetadataUrl,
      );

      // Trigger Local Notification
      try {
        await NotificationService().showNotification(
          id: mintedNFT.tokenId % 100000,
          title: 'NFT Submitted for Review! 📋',
          body: 'Artwork "${mintedNFT.name}" is pending admin approval.\nToken ID: ${mintedNFT.tokenId}'
        );
      } catch (e) {
        if (kDebugMode) { debugPrint('Failed to show notification: $e'); }
      }

      // Reset form
      _nameController.clear();
      _descController.clear();
      _priceController.text = '0.01';
      setState(() {
        _imageBase64 = null;
        _imageBytes = null;
        _selectedCategory = NFTCategory.technology;
        _auctionDurationMinutes = 5;
        _statusMessage = '';
      });

    } catch (e) {
      if (!mounted) return;
      
      // â•â•â• TARGETED ERROR MESSAGES â•â•â•
      String errorMessage = e.toString().replaceFirst("Exception: ", "");
      
      if (e.toString().contains('User rejected') || e.toString().contains('cancelled')) {
        errorMessage = 'User rejected the transaction';
      } else if (e.toString().contains('insufficient funds') || e.toString().contains('gas')) {
        errorMessage = 'Blockchain transaction failed';
      } else if (e.toString().contains('network') || e.toString().contains('Sepolia')) {
        errorMessage = 'Wrong network. Please switch to Sepolia Testnet in MetaMask.';
      } else if (e.toString().contains('IPFS') || e.toString().contains('Pinata') || e.toString().contains('upload')) {
        errorMessage = 'IPFS upload failed. Please check your internet and try again.';
      } else if (e.toString().contains('Transaction failed on-chain') || e.toString().contains('revert')) {
        errorMessage = 'Smart contract rejected the transaction. Please try again.';
      } else if (e.toString().contains('Firestore fail')) {
        errorMessage = 'Blockchain success but database update failed. Your NFT is safe and will sync later.';
      } else if (e.toString().contains('timed out')) {
        errorMessage = 'Transaction timed out. Check Etherscan for status.';
      }

      NotificationManager.show(
        context: context,
        title: 'Mint Failed',
        message: errorMessage,
        type: NotificationType.error,
      );
      
      if (kDebugMode) { debugPrint('[MINT FAILED] âŒ $e'); }
      if (kDebugMode) { debugPrint('[MINT FAILED] No ghost NFT was created â€” Firestore is clean.'); }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isMinting = false;
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  void _showSuccessDialog(String logoName, {String? ipfsImageUrl, String? ipfsMetadataUrl}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
        content: RefreshIndicator(
      onRefresh: () async { setState(() {}); },
      child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 60,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Submitted for Review! 📋',
                style: AppTextStyles.h2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '"$logoName" has been submitted for admin review. Once approved, you will be able to mint it to the blockchain.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),

              // IPFS Storage Info
              if (ipfsImageUrl != null || ipfsMetadataUrl != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.frozenBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.frozenBlue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_done, color: AppColors.frozenBlue, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Stored on IPFS (Pinata)',
                            style: AppTextStyles.labelMedium.copyWith(color: AppColors.frozenBlue),
                          ),
                        ],
                      ),
                      if (ipfsImageUrl != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.image, color: AppColors.textSecondary, size: 14),
                            const SizedBox(width: 6),
                            Text('Image: ', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                            Expanded(
                              child: Text(
                                '${ipfsImageUrl.substring(0, 30)}...',
                                style: AppTextStyles.mono.copyWith(color: AppColors.textPrimary, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: ipfsImageUrl));
                                NotificationManager.show(context: context, title: 'Copied', message: 'IPFS Image URL copied!', type: NotificationType.info);
                              },
                              child: const Icon(Icons.copy, size: 14, color: AppColors.frozenBlue),
                            ),
                          ],
                        ),
                      ],
                      if (ipfsMetadataUrl != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.description, color: AppColors.textSecondary, size: 14),
                            const SizedBox(width: 6),
                            Text('Metadata: ', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                            Expanded(
                              child: Text(
                                '${ipfsMetadataUrl.substring(0, 30)}...',
                                style: AppTextStyles.mono.copyWith(color: AppColors.textPrimary, fontSize: 10),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: ipfsMetadataUrl));
                                NotificationManager.show(context: context, title: 'Copied', message: 'IPFS Metadata URL copied!', type: NotificationType.info);
                              },
                              child: const Icon(Icons.copy, size: 14, color: AppColors.frozenBlue),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                text: 'OK',
                onPressed: () {
                  Navigator.pop(context);
                  widget.onMintSuccess?.call();
                },
              ),
            ],
          ),
        ),
    ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isMinting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          NotificationManager.show(
            context: context,
            title: 'Please Wait',
            message: 'Cannot go back while minting is in progress',
            type: NotificationType.warning,
          );
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Upload Artwork', style: AppTextStyles.h3),
        centerTitle: true,
        elevation: 0,
      ),
      body: !_web3.isConnected
          ? _buildConnectPrompt()
          : SingleChildScrollView(
              padding: const EdgeInsets.only(left: AppSpacing.xl, right: AppSpacing.xl, top: AppSpacing.xl, bottom: 40),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Upload area
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 180, // Reduced from 220 to prevent vertical crowding
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.15),
                              AppColors.frozenBlue.withValues(alpha: 0.15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xxl),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                        child: _imageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.xxl - 2),
                                child: Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(AppSpacing.xl),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.cloud_upload,
                                      size: 50,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  const Text(
                                    'Tap to upload artwork',
                                    style: AppTextStyles.labelLarge,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'PNG, JPG, GIF • Max 10MB',
                                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Name field
                    _buildLabel('Artwork Name'),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _nameController,
                      style: AppTextStyles.bodyMedium,
                      decoration: _inputDecoration('Enter artwork name'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Description field
                    _buildLabel('Description'),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _descController,
                      style: AppTextStyles.bodyMedium,
                      maxLines: 3,
                      decoration: _inputDecoration('Artwork description and copyright info'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Description is required' : null,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Category field
                    _buildLabel('Category'),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: AppTextStyles.bodyMedium,
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          items: NFTCategory.values.map((category) {
                            return DropdownMenuItem(
                              value: category,
                              child: Row(
                                children: [
                                  Icon(
                                    _getCategoryIcon(category),
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Text(category),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _selectedCategory = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Starting price field
                    // Starting price field
                    _buildLabel('Starting Price (ETH)'),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Wallet Balance: ${_web3.balance.toStringAsFixed(4)} ETH',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _priceController,
                      style: AppTextStyles.bodyMedium,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: _inputDecoration('0.00').copyWith(
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: Image.asset('assets/images/logo.png', width: 24, height: 24, fit: BoxFit.contain),
                        ),
                        suffixText: 'ETH',
                        suffixStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Price is required';
                        final price = double.tryParse(v);
                        if (price == null || price <= 0) return 'Invalid price';
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Wallet balance is shown for reference only. Starting Price is not limited by your current balance.',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Auction Duration field
                    _buildLabel('Auction Duration'),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButtonFormField<int>(
                          initialValue: _auctionDurationMinutes,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: AppTextStyles.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                          items: const [
                            DropdownMenuItem(
                              value: 5,
                              child: Row(
                                children: [
                                  Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
                                  SizedBox(width: AppSpacing.md),
                                  Text('5 Minutes'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 10,
                              child: Row(
                                children: [
                                  Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
                                  SizedBox(width: AppSpacing.md),
                                  Text('10 Minutes'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 25,
                              child: Row(
                                children: [
                                  Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
                                  SizedBox(width: AppSpacing.md),
                                  Text('25 Minutes'),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 30,
                              child: Row(
                                children: [
                                  Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
                                  SizedBox(width: AppSpacing.md),
                                  Text('30 Minutes'),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _auctionDurationMinutes = v!),
                          validator: (v) => v == null ? 'Please select auction duration' : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // Info card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.frozenBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.frozenBlue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.frozenBlue),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Your artwork will be reviewed by admin. Once approved, you can mint it to the blockchain and start an auction at your convenience.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.frozenBlue),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Submit button
                    // Show contract initializing state
                    if (_isInitializingContract)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accentOrange,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'Initializing Smart Contract...',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.accentOrange),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ElevatedButton(
                      onPressed: (_isLoading || _isMinting || _isProcessing || _isInitializingContract) ? null : _submitForReview,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: AppColors.accentOrange,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        elevation: _isLoading ? 0 : 4,
                        shadowColor: AppColors.accentOrange.withValues(alpha: 0.4),
                      ),
                      child: _isLoading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Flexible(
                                  child: Text(
                                    _statusMessage,
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.labelMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload, size: 20),
                                SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    'Mint \u0026 Submit for Review',
                                    style: AppTextStyles.labelLarge,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildConnectPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.account_balance_wallet,
                size: 64,
                color: AppColors.accentOrange,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Wallet Not Connected',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Connect wallet to upload artwork',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            PrimaryButton(
              text: 'Connect Wallet',
              icon: Icons.link,
              onPressed: () async {
                try {
                  await WalletUtils.showConnectDialog(context, _web3);
                } catch (e) {
                  if (!mounted) return;
                  NotificationManager.show(
                    context: context,
                    title: 'Error',
                    message: e.toString().replaceFirst("Exception: ", ""),
                    type: NotificationType.error,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.labelLarge,
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.danger, width: 2),
      ),
      contentPadding: const EdgeInsets.all(AppSpacing.lg),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Technology':
        return Icons.computer;
      case 'Food & Beverage':
        return Icons.restaurant;
      case 'Fashion':
        return Icons.checkroom;
      case 'Gaming':
        return Icons.sports_esports;
      case 'Education':
        return Icons.school;
      case 'Corporate':
        return Icons.business;
      default:
        return Icons.category;
    }
  }
}

