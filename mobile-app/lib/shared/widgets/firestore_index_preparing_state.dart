import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';

/// Premium Web3 fallback widget shown when Firestore queries fail
/// (e.g. missing indexes, permission errors, network failures).
///
/// Replaces raw red error screens with a glassmorphic, animated
/// blockchain-themed UI that keeps the user informed without
/// exposing any internal Firebase details.
class FirestoreIndexPreparingState extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  const FirestoreIndexPreparingState({
    super.key,
    this.title = 'Marketplace Data Preparing',
    this.message = 'This feature is currently initializing blockchain indexes. '
        'Please try again shortly.',
    this.icon = Icons.sync,
    this.onRetry,
    this.onBack,
  });

  @override
  State<FirestoreIndexPreparingState> createState() =>
      _FirestoreIndexPreparingStateState();
}

class _FirestoreIndexPreparingStateState
    extends State<FirestoreIndexPreparingState>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Subtle pulse glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Icon rotation
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Fade in
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xxxl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Animated Icon Container ──
              _buildAnimatedIcon(),
              const SizedBox(height: AppSpacing.xxl),

              // ── Glassmorphic Card ──
              _buildInfoCard(),
              const SizedBox(height: AppSpacing.xxl),

              // ── Action Buttons ──
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.15 * _pulseAnimation.value),
                AppColors.primary.withValues(alpha: 0.05 * _pulseAnimation.value),
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(
                  color: AppColors.primary.withValues(
                    alpha: 0.3 + (0.3 * _pulseAnimation.value),
                  ),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(
                      alpha: 0.1 * _pulseAnimation.value,
                    ),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: widget.icon == Icons.sync
                  ? AnimatedBuilder(
                      animation: _rotateController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _rotateController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: Icon(
                        widget.icon,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    )
                  : Icon(
                      widget.icon,
                      color: AppColors.primary,
                      size: 28,
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                widget.title,
                style: AppTextStyles.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              // Message
              Text(
                widget.message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Shimmer loading bar
              _buildShimmerBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerBar() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          height: 3,
          width: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.1),
                AppColors.primary.withValues(
                  alpha: 0.4 * _pulseAnimation.value,
                ),
                AppColors.primary.withValues(alpha: 0.1),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onRetry != null)
          SizedBox(
            width: 200,
            child: OutlinedButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
            ),
          ),
        if (widget.onRetry != null && widget.onBack != null)
          const SizedBox(height: AppSpacing.md),
        if (widget.onBack != null)
          TextButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Go Back'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
