import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/shared/models/auction.dart';

class BidDialog extends StatefulWidget {
  final double currentBid;
  final double startingPrice;
  final double userBalance;
  final Function(double) onBid;

  const BidDialog({
    super.key,
    required this.currentBid,
    required this.startingPrice,
    required this.userBalance,
    required this.onBid,
  });

  @override
  State<BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {
  late TextEditingController _controller;
  String? _error;

  double get minBid =>
      widget.currentBid > 0 ? widget.currentBid + Auction.getMinimumIncrement(widget.currentBid) : widget.startingPrice;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: minBid.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final value = double.tryParse(_controller.text);
    setState(() {
      if (value == null) {
        _error = 'Enter a valid number';
      } else if (widget.currentBid > 0 && value <= widget.currentBid) {
        _error = 'Your bid must be higher than current highest bid';
      } else if (value < minBid) {
        _error = 'Minimum bid: ${minBid.toStringAsFixed(2)} ETH';
      } else if (value > widget.userBalance) {
        _error = 'Insufficient balance';
      } else {
        _error = null;
      }
    });
  }

  void _addIncrement(double amount) {
    final baseValue = widget.currentBid > 0 ? widget.currentBid : widget.startingPrice;
    final currentValue = double.tryParse(_controller.text) ?? baseValue;
    final startingPoint = currentValue <= widget.currentBid ? widget.currentBid : currentValue;
    final newValue = (startingPoint + amount).toStringAsFixed(2);
    _controller.text = newValue;
    _validate();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: AppShadows.soft,
        ),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.gavel,
                      color: AppColors.accentOrange,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bid Now',
                          style: AppTextStyles.h3,
                        ),
                        Text(
                          'Enter your bid amount',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Current bid info
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Starting Price', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                        Text('${widget.startingPrice.toStringAsFixed(2)} ETH', style: AppTextStyles.subtitle1),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Current Highest Bid', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                        Text('${widget.currentBid.toStringAsFixed(2)} ETH', style: AppTextStyles.subtitle1.copyWith(color: AppColors.accentOrange)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.border),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Minimum Next Bid', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textPrimary)),
                        Text('${minBid.toStringAsFixed(2)} ETH', style: AppTextStyles.h3.copyWith(color: AppColors.frozenBlue)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Input
              TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => _validate(),
                style: AppTextStyles.h2,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceLight,
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
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Image.asset('assets/images/logo.png', width: 24, height: 24, fit: BoxFit.contain),
                  ),
                  suffixText: 'ETH',
                  suffixStyle: AppTextStyles.h3.copyWith(color: AppColors.textSecondary),
                  errorText: _error,
                  errorStyle: AppTextStyles.labelSmall.copyWith(color: AppColors.danger),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Min bid hint & Balance
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Minimum: ${minBid.toStringAsFixed(2)} ETH',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    'Balance: ${widget.userBalance.toStringAsFixed(2)} ETH',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.success),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Quick increment buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildIncrementButton('+0.01', 0.01),
                  _buildIncrementButton('+0.05', 0.05),
                  _buildIncrementButton('+0.10', 0.10),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Warning note
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.success, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your bid only updates the leaderboard.\nNo blockchain transaction will occur.',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.success),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          side: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: AppTextStyles.labelMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _error == null
                          ? () {
                              final value = double.tryParse(_controller.text);
                              if (value != null) {
                                widget.onBid(value);
                                Navigator.pop(context);
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: AppColors.accentOrange,
                        foregroundColor: AppColors.textPrimary,
                        disabledBackgroundColor: AppColors.surfaceLight,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.gavel),
                          SizedBox(width: AppSpacing.sm),
                          Text(
                            'Bid Now',
                            style: AppTextStyles.labelLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }

  Widget _buildIncrementButton(String label, double amount) {
    return ActionChip(
      label: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
      ),
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      onPressed: () => _addIncrement(amount),
    );
  }
}

