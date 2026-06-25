import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/shared/widgets/primary_button.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/shared/models/logo_nft.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';

class ReAuctionDialog extends StatefulWidget {
  final LogoNFT logo;

  const ReAuctionDialog({
    super.key,
    required this.logo,
  });

  static Future<void> show(BuildContext context, LogoNFT logo) {
    return showDialog(
      context: context,
      builder: (context) => ReAuctionDialog(logo: logo),
    );
  }

  @override
  State<ReAuctionDialog> createState() => _ReAuctionDialogState();
}

class _ReAuctionDialogState extends State<ReAuctionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  int _selectedDuration = 86400; // Default 24 hours
  bool _isLoading = false;

  final List<Map<String, dynamic>> _durations = [
    {'label': '30 Seconds', 'value': 30},
    {'label': '1 Minute', 'value': 60},
    {'label': '25 Minutes', 'value': 1500},
    {'label': '30 Minutes', 'value': 1800},
    {'label': '1 Hour', 'value': 3600},
    {'label': '6 Hours', 'value': 21600},
    {'label': '12 Hours', 'value': 43200},
    {'label': '24 Hours', 'value': 86400},
    {'label': '3 Days', 'value': 259200},
    {'label': '7 Days', 'value': 604800},
  ];

  @override
  void initState() {
    super.initState();
    _priceController.text = widget.logo.price.toString();
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
      await FirestoreService.instance.requestReAuctionWithSettings(
        widget.logo.tokenId,
        _selectedDuration,
        newPrice,
      );

      if (mounted) {
        Navigator.pop(context);
        NotificationManager.show(
          context: context,
          title: 'Re-Auction Started',
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
      backgroundColor: AppColors.surface,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Re-Auction NFT', style: AppTextStyles.h3),
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
                'Review your NFT and set new auction parameters. The auction will start immediately.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Premium Preview
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.network(
                        widget.logo.imageUrl.replaceFirst('ipfs://', 'https://ipfs.io/ipfs/'),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80, height: 80,
                          color: AppColors.surface,
                          child: const Icon(Icons.broken_image, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.logo.name, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text('Category: ${widget.logo.category}', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                          const SizedBox(height: 4),
                          Text('Token #${widget.logo.tokenId}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Starting Price
              Text('New Starting Price (ETH)', style: AppTextStyles.labelMedium),
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
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                ],
                style: AppTextStyles.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'e.g. 0.05',
                  prefixIcon: const Icon(Icons.monetization_on_outlined, color: AppColors.textSecondary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a price';
                  final price = double.tryParse(value);
                  if (price == null || price <= 0) return 'Invalid price';
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
              const SizedBox(height: AppSpacing.lg),

              // Duration
              Text('Auction Duration', style: AppTextStyles.labelMedium),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDuration,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                    items: _durations.map((duration) {
                      return DropdownMenuItem<int>(
                        value: duration['value'] as int,
                        child: Text(duration['label'] as String, style: AppTextStyles.bodyLarge),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedDuration = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  text: 'Start Re-Auction',
                  onPressed: _submitRequest,
                  isLoading: _isLoading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
