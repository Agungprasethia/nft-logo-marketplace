import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/web3_service.dart';
import '../../../shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import '../../../core/utils/notification_manager.dart';
import '../../../shared/models/app_notification.dart';

class RelistAuctionDialog extends StatefulWidget {
  final LogoNFT logo;

  const RelistAuctionDialog({super.key, required this.logo});

  static Future<void> show(BuildContext context, LogoNFT logo) {
    return showDialog(
      context: context,
      builder: (_) => RelistAuctionDialog(logo: logo),
    );
  }

  @override
  State<RelistAuctionDialog> createState() => _RelistAuctionDialogState();
}

class _RelistAuctionDialogState extends State<RelistAuctionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  int _selectedDuration = 86400; // Default 24 hours
  bool _isLoading = false;

  final List<Map<String, dynamic>> _durations = [
    {'label': '25 Minutes', 'value': 1500},
    {'label': '30 Minutes', 'value': 1800},
    {'label': '12 Hours', 'value': 43200},
    {'label': '24 Hours', 'value': 86400},
    {'label': '3 Days', 'value': 259200},
    {'label': '7 Days', 'value': 604800},
  ];

  @override
  void initState() {
    super.initState();
    _priceController.text = widget.logo.price.toString();
    
    // Check if current duration exists in options
    final existingDuration = widget.logo.auctionDuration ?? 86400;
    if (_durations.any((d) => d['value'] == existingDuration)) {
      _selectedDuration = existingDuration;
    } else {
      _durations.insert(0, {'label': 'Previous (${existingDuration ~/ 3600}h)', 'value': existingDuration});
      _selectedDuration = existingDuration;
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final newPrice = double.parse(_priceController.text);
      final web3 = Web3Service.instance;
      final currentWallet = web3.currentAddress;

      if (currentWallet == null) throw Exception('Wallet not connected');

      // 1. Create on-chain using identical workflow
      await web3.createAuctionOnChain(
        tokenId: widget.logo.tokenId,
        creatorAddress: widget.logo.creatorWallet,
        startingPrice: newPrice,
        durationSeconds: _selectedDuration,
      );

      // 2. Start on Firestore with explicit new price/duration
      await FirestoreService.instance.startAuction(
        widget.logo.tokenId,
        newPrice: newPrice,
        newDuration: _selectedDuration,
        userWallet: currentWallet,
      );

      if (mounted) {
        Navigator.pop(context);
        NotificationManager.show(
          context: context,
          title: 'Relist Successful',
          message: 'Your NFT has been relisted successfully.',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationManager.show(
          context: context,
          title: 'Error',
          message: e.toString().replaceFirst("Exception: ", ""),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Relist Auction', style: AppTextStyles.h3),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Relist ${widget.logo.name} by setting a new price and duration.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              
              Text('Starting Price (ETH)', style: AppTextStyles.labelMedium),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Wallet Balance: ${Web3Service.instance.balance.toStringAsFixed(4)} ETH',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g. 0.05',
                  hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  prefixIcon: const Icon(Icons.currency_bitcoin, color: AppColors.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.primary)),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter starting price';
                  final price = double.tryParse(val);
                  if (price == null || price <= 0) return 'Enter a valid price > 0';
                  return null;
                },
              ),
              const SizedBox(height: 6),
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
              const SizedBox(height: AppSpacing.md),
              
              Text('Auction Duration', style: AppTextStyles.labelMedium),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDuration,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.textPrimary),
                    items: _durations.map((d) {
                      return DropdownMenuItem<int>(
                        value: d['value'] as int,
                        child: Text(d['label'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedDuration = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: _isLoading 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Confirm Relist', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
