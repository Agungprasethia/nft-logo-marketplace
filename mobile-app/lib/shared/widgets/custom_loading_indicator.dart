import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';

class CustomLoadingIndicator extends StatefulWidget {
  final double size;
  final Color? color;
  final String? message;

  const CustomLoadingIndicator({
    super.key,
    this.size = 40.0,
    this.color,
    this.message,
  });

  @override
  State<CustomLoadingIndicator> createState() => _CustomLoadingIndicatorState();
}

class _CustomLoadingIndicatorState extends State<CustomLoadingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RotationTransition(
            turns: _controller,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.size / 2),
                gradient: SweepGradient(
                  colors: [
                    AppColors.surface,
                    widget.color ?? AppColors.primary,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(3.0),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.message!,
              style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
    );
  }
}
