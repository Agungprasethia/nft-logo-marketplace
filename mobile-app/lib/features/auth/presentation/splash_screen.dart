import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart';
import 'package:nft_logo_marketplace/core/services/auth_service.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/home_page.dart';
import 'package:nft_logo_marketplace/features/auth/presentation/login_page.dart';
import 'package:nft_logo_marketplace/features/admin/presentation/admin_dashboard.dart';
import 'package:nft_logo_marketplace/core/utils/route_utils.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/shared/models/app_notification.dart';
import 'package:nft_logo_marketplace/shared/widgets/custom_loading_indicator.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';

enum SplashState {
  initializing,
  restoringSession,
  validatingWallet,
  wrongNetwork,
  authenticated,
  unauthenticated,
  error,
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  
  final ValueNotifier<SplashState> _splashState = ValueNotifier(SplashState.initializing);
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
    
    // Defer initialization to avoid blocking the first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runAsyncBoot();
    });
  }

  Future<void> _runAsyncBoot() async {
    try {
      // 1. Mobile Notifications Init (Silent, no await needed for routing)
      if (!kIsWeb) {
        FlutterLocalNotificationsPlugin().initialize(
          const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        ).catchError((e) { 
          if (kDebugMode) { debugPrint('Notification init error: $e'); }
          return false;
        });
      }

      // 2. Web3 Base Initialization (Background)
      Web3Service.instance.initialize().catchError((e) {
        if (kDebugMode) { debugPrint('[WEB3] âš ï¸ Init Error (non-fatal): $e'); }
      });

      // 3. Handle Admin Mode Routing
      if (isAdminMode) {
        final user = AuthService.instance.currentUser;
        if (user != null) {
          _navigateTo(const AdminDashboard());
        } else {
          _navigateTo(const LoginPage());
        }
        return;
      }

      // 4. Restore Session
      _splashState.value = SplashState.restoringSession;
      final hasSession = await SessionService.instance.hasValidSession();
      
      if (hasSession) {
        _splashState.value = SplashState.authenticated;
        _performBackgroundValidation();
        _navigateTo(const HomePage());
      } else {
        _splashState.value = SplashState.unauthenticated;
        _navigateTo(const HomePage());
      }

    } catch (e) {
      if (kDebugMode) { debugPrint('Boot error: $e'); }
      _splashState.value = SplashState.error;
      _navigateTo(const HomePage());
    }
  }

  void _performBackgroundValidation() async {
    try {
      final session = await SessionService.instance.getSession();
      final success = await Future.any([
        Web3Service.instance.connectWallet(
          walletName: session?.walletProvider ?? 'metamask',
          restoreSession: true,
        ),
        Future.delayed(const Duration(seconds: 8), () => false),
      ]);
      
      if (success) {
        await SessionService.instance.updateLastConnected();
        
        // Check for wrong network after successful connection
        if (Web3Service.instance.chainId != 11155111) {
          if (!mounted) return;
          NotificationManager.show(
            context: context,
            type: NotificationType.warning,
            title: 'Wrong Network',
            message: 'Wrong blockchain network detected.',
          );
        } else {
          if (!mounted) return;
          NotificationManager.show(
            context: context,
            type: NotificationType.success,
            title: 'Session Restored',
            message: 'Wallet session restored successfully.',
          );
        }
      } else {
        // Silent restore failed
        if (!mounted) return;
        NotificationManager.show(
          context: context,
          type: NotificationType.error,
          title: 'Validation Failed',
          message: 'Session validation failed. Please reconnect.',
        );
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('Background validation error: $e'); }
    }
  }

  void _navigateTo(Widget destination) {
    if (_isDisposed) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  String _getStatusText(SplashState state) {
    switch (state) {
      case SplashState.initializing: return 'Initializing...';
      case SplashState.restoringSession: return 'Restoring Secure Wallet Session...';
      case SplashState.validatingWallet: return 'Validating Wallet...';
      case SplashState.wrongNetwork: return 'Wrong Network Detected';
      case SplashState.authenticated: return 'Welcome back!';
      case SplashState.unauthenticated: return 'Ready to connect';
      case SplashState.error: return 'Initialization Error';
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    _splashState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Radial gradient background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Pulsing glow calculation
                final glowIntensity = 0.4 + (0.2 * _controller.value);
                
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated Logo Circle
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: glowIntensity * 0.8),
                                blurRadius: 80 * _scaleAnimation.value,
                                spreadRadius: 20 * _scaleAnimation.value,
                              ),
                              BoxShadow(
                                color: AppColors.secondary.withValues(alpha: glowIntensity * 0.6),
                                blurRadius: 120 * _scaleAnimation.value,
                                spreadRadius: 10 * _scaleAnimation.value,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            width: 160,
                            height: 160,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // App Name
                        Text(
                          'LEO',
                          style: AppTextStyles.display.copyWith(
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tagline
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            'Logo Exchange & Ownership',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.primary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 64),

                        // Loading indicator
                        const CustomLoadingIndicator(size: 32),
                        
                        const SizedBox(height: 24),

                        ValueListenableBuilder<SplashState>(
                          valueListenable: _splashState,
                          builder: (context, state, child) {
                            return Text(
                              _getStatusText(state),
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.textSecondary,
                                letterSpacing: 1,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
