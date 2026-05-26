import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';

class PremiumNotification extends StatefulWidget {
  final String title;
  final String message;
  final NotificationType type;
  final VoidCallback onDismissed;
  final VoidCallback? onTap;

  const PremiumNotification({
    super.key,
    required this.title,
    required this.message,
    required this.type,
    required this.onDismissed,
    this.onTap,
  });

  @override
  State<PremiumNotification> createState() => _PremiumNotificationState();
}

class _PremiumNotificationState extends State<PremiumNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();

    // Auto dismiss after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismissed();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  Color _getPrimaryColor() {
    switch (widget.type) {
      case NotificationType.success:
        return AppColors.success;
      case NotificationType.error:
        return AppColors.danger;
      case NotificationType.warning:
        return AppColors.accentOrange;
      case NotificationType.info:
        return AppColors.primary;
      case NotificationType.web3:
        return const Color(0xFF00E5FF); // Cyan
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case NotificationType.success:
        return Icons.check_circle_outline;
      case NotificationType.error:
        return Icons.error_outline;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.info:
        return Icons.info_outline;
      case NotificationType.web3:
        return Icons.account_balance_wallet_outlined;
    }
  }

  List<Color> _getGradient() {
    switch (widget.type) {
      case NotificationType.web3:
        return [
          const Color(0xFF9B51E0).withValues(alpha: 0.2), // Purple
          const Color(0xFF00E5FF).withValues(alpha: 0.2), // Cyan
        ];
      case NotificationType.success:
        return [
          AppColors.success.withValues(alpha: 0.2),
          AppColors.success.withValues(alpha: 0.05),
        ];
      case NotificationType.error:
        return [
          AppColors.danger.withValues(alpha: 0.2),
          AppColors.danger.withValues(alpha: 0.05),
        ];
      case NotificationType.warning:
        return [
          AppColors.accentOrange.withValues(alpha: 0.2),
          AppColors.accentOrange.withValues(alpha: 0.05),
        ];
      case NotificationType.info:
        return [
          AppColors.primary.withValues(alpha: 0.2),
          AppColors.primary.withValues(alpha: 0.05),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return SafeArea(
      child: Align(
        alignment: isDesktop ? Alignment.topRight : Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(
            top: AppSpacing.md,
            right: isDesktop ? AppSpacing.xl : AppSpacing.md,
            left: isDesktop ? 0 : AppSpacing.md,
          ),
          child: Material(
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: child,
                    ),
                  ),
                );
              },
              child: GestureDetector(
                onTap: () {
                  if (widget.onTap != null) widget.onTap!();
                  _dismiss();
                },
                onVerticalDragEnd: (details) {
                  if (details.primaryVelocity! < 0) {
                    _dismiss();
                  }
                },
                onHorizontalDragEnd: (details) {
                  if (isDesktop && details.primaryVelocity! > 0) {
                    _dismiss();
                  }
                },
                child: Container(
                  width: isDesktop ? 400 : double.infinity,
                  constraints: const BoxConstraints(minHeight: 80),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.15),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.8),
                          gradient: LinearGradient(
                            colors: _getGradient(),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(
                                _getIcon(),
                                color: primaryColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    style: AppTextStyles.h3.copyWith(
                                      color: primaryColor,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.message,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              onPressed: _dismiss,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
