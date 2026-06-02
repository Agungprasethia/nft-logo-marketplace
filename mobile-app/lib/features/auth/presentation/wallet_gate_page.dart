import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';
import 'package:nft_logo_marketplace/features/nft/presentation/home_page.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_spacing.dart';
import 'package:nft_logo_marketplace/core/utils/notification_manager.dart';
import 'package:nft_logo_marketplace/shared/models/notification_model.dart';

/// Premium wallet gate page — user must connect wallet before accessing the marketplace.
/// Inspired by OpenSea, Rainbow Wallet, and Foundation connect flows.
class WalletGatePage extends StatefulWidget {
  const WalletGatePage({super.key});

  @override
  State<WalletGatePage> createState() => _WalletGatePageState();
}

class _WalletGatePageState extends State<WalletGatePage>
    with TickerProviderStateMixin {
  final _web3 = Web3Service.instance;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _pulseAnimation;
  bool _isConnecting = false;
  String? _lastConnectedWallet;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();

    // Listen for wallet connection changes
    _web3.addListener(_onWalletChanged);
    _loadLastWallet();
  }

  Future<void> _loadLastWallet() async {
    final wallet = await SessionService.instance.getLastConnectedWallet();
    if (wallet != null && mounted) {
      setState(() => _lastConnectedWallet = wallet);
    }
  }

  @override
  void dispose() {
    _web3.removeListener(_onWalletChanged);
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onWalletChanged() {
    if (_web3.isConnected && mounted) {
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomePage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  Future<void> _connectWallet() async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);

    try {
      // Ensure Web3 contracts are initialized before connecting wallet
      if (kDebugMode) { debugPrint('[WEB3] Ensuring Web3 initialization before wallet connect...'); }
      await Web3Service.instance.initialize();

      if (!mounted) return;
      await WalletUtils.showConnectDialog(context, _web3);
      // _onWalletChanged will handle navigation if connected
    } catch (e) {
      if (!mounted) return;
      NotificationManager.show(
        context: context,
        title: 'Error',
        message: e.toString().replaceFirst("Exception: ", ""),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ─── Background Gradient Orbs ───
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _GlowOrbsPainter(
                    intensity: _pulseAnimation.value,
                  ),
                );
              },
            ),
          ),

          // ─── Content ───
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.xl,
                ),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: AnimatedBuilder(
                    animation: _slideAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _slideAnimation.value),
                        child: child,
                      );
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ─── Logo & Branding ───
                        _buildLogo(),
                        const SizedBox(height: 48),

                        // ─── Title ───
                        Text(
                          'L E O',
                          style: AppTextStyles.display.copyWith(
                            fontSize: 42,
                            letterSpacing: 12,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Logo Exchange & Ownership',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Connect your wallet to start discovering,\ncollecting & auctioning verified logo NFTs',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),

                        // ─── Connect Button ───
                        _buildConnectButton(),
                        _buildLastConnected(),
                        const SizedBox(height: 24),

                        // ─── Features Preview ───
                        _buildFeatureChips(),
                        const SizedBox(height: 48),

                        // ─── Footer ───
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final glow = _pulseAnimation.value;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35 * glow),
                blurRadius: 80,
                spreadRadius: 20,
              ),
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.25 * glow),
                blurRadius: 120,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/logo.png',
            width: 140,
            height: 140,
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }

  Widget _buildConnectButton() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: _isConnecting ? null : _connectWallet,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
              child: _isConnecting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 14),
                        Text(
                          'Connecting...',
                          style: AppTextStyles.labelLarge,
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.account_balance_wallet_rounded,
                          color: AppColors.textPrimary,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Connect Wallet',
                          style: AppTextStyles.labelLarge,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLastConnected() {
    if (_lastConnectedWallet == null) return const SizedBox.shrink();

    final shortWallet = '${_lastConnectedWallet!.substring(0, 6)}...${_lastConnectedWallet!.substring(_lastConnectedWallet!.length - 4)}';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Last used: $shortWallet',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChips() {
    final features = [
      (Icons.brush_outlined, 'Logo Marketplace'),
      (Icons.gavel_rounded, 'Live Auctions'),
      (Icons.verified_outlined, 'On-Chain Ownership'),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: features.map((f) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f.$1, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                f.$2,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sepolia Testnet',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Powered by Ethereum & WalletConnect',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

/// Custom painter for animated background glow orbs
class _GlowOrbsPainter extends CustomPainter {
  final double intensity;

  _GlowOrbsPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    // Top-left purple orb
    final paint1 = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 120);
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.2),
      180,
      paint1,
    );

    // Bottom-right secondary orb
    final paint2 = Paint()
      ..color = AppColors.secondary.withValues(alpha: 0.06 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 150);
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.75),
      200,
      paint2,
    );

    // Center accent orb
    final paint3 = Paint()
      ..color = AppColors.accentOrange.withValues(alpha: 0.03 * intensity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      150,
      paint3,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowOrbsPainter oldDelegate) {
    return oldDelegate.intensity != intensity;
  }
}
