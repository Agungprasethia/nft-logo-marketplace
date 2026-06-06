import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/utils/wallet_utils.dart';

class WalletConnectModal extends StatefulWidget {
  final String title;
  final String message;

  const WalletConnectModal({
    super.key,
    this.title = 'Connect Wallet Required',
    this.message = 'Please connect your wallet to participate in the marketplace.',
  });

  static bool _isDialogOpen = false;

  static Future<bool> show(BuildContext context, {
    String title = 'Connect Wallet Required',
    String message = 'Please connect your wallet to access this feature.',
  }) async {
    if (_isDialogOpen) return false;
    _isDialogOpen = true;

    try {
      final result = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Wallet Connect Modal',
        barrierColor: Colors.black.withValues(alpha: 0.8),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return WalletConnectModal(title: title, message: message);
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        },
      );
      return result ?? false;
    } finally {
      _isDialogOpen = false;
    }
  }

  @override
  State<WalletConnectModal> createState() => _WalletConnectModalState();
}

class _WalletConnectModalState extends State<WalletConnectModal>
    with WidgetsBindingObserver {
  bool _isConnecting = false;
  bool _isClosing = false;

  // Resume-polling state
  Timer? _resumePoller;
  bool _isCheckingManually = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen for wallet connection changes — auto-dismiss when connected
    Web3Service.instance.addListener(_onWeb3Changed);
    // Check immediately in case already connected (e.g. session restored)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Web3Service.instance.isConnected) {
        _safePop(true);
      }
    });
  }

  void _safePop(bool result) {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    _cancelResumePoller();
    Web3Service.instance.removeListener(_onWeb3Changed);
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _cancelResumePoller();
    WidgetsBinding.instance.removeObserver(this);
    Web3Service.instance.removeListener(_onWeb3Changed);
    super.dispose();
  }

  // ── Polling helpers ────────────────────────────────────────────────────

  void _cancelResumePoller() {
    _resumePoller?.cancel();
    _resumePoller = null;
  }

  /// Starts aggressive 500 ms polling for up to [durationSeconds].
  /// Silently closes the modal if the connection is detected.
  void _startResumePolling({int durationSeconds = 30}) {
    _cancelResumePoller(); // avoid duplicates

    int elapsed = 0;
    const interval = 500; // ms

    _resumePoller = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        elapsed += interval;

        if (!mounted || _isClosing) {
          timer.cancel();
          return;
        }

        // Connected — auto-close silently
        if (Web3Service.instance.isConnected) {
          timer.cancel();
          if (mounted && !_isClosing) setState(() => _isConnecting = false);
          _safePop(true);
          return;
        }

        // Polling window expired — stop silently, keep UI as-is
        if (elapsed >= durationSeconds * 1000) {
          timer.cancel();
          if (mounted && !_isClosing) {
            setState(() => _isConnecting = false);
          }
        }
      },
    );
  }

  // ── AppLifecycle ───────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isConnecting) {
      // User came back from MetaMask — start aggressive 500 ms polling for 30 s.
      // This works even when the deep-link callback is swallowed by OEM ROMs.
      _startResumePolling(durationSeconds: 30);
    } else if (state == AppLifecycleState.paused) {
      // App went to background — stop polling to save battery
      _cancelResumePoller();
    }
  }

  // ── Web3 listener ──────────────────────────────────────────────────────

  void _onWeb3Changed() {
    if (!mounted) return;
    if (Web3Service.instance.isConnected) {
      // Wallet just connected — dismiss modal immediately
      if (mounted && !_isClosing) setState(() => _isConnecting = false);
      _safePop(true);
    }
  }

  // ── Connection trigger ─────────────────────────────────────────────────

  Future<void> _handleConnect() async {
    if (_isConnecting || _isClosing) return;
    // Guard: already connected — just close
    if (Web3Service.instance.isConnected) {
      _safePop(true);
      return;
    }

    setState(() => _isConnecting = true);

    try {
      await WalletUtils.showConnectDialog(context, Web3Service.instance);
      // If connectWallet() returned and we're still not connected, the
      // listener or resume-poller will handle it. Just reset the spinner.
      if (mounted && !Web3Service.instance.isConnected && !_isClosing) {
        setState(() => _isConnecting = false);
      }
    } catch (_) {
      // Suppress errors — keep retrying silently via polling
      if (mounted && !_isClosing) setState(() => _isConnecting = false);
    }
  }

  // ── Manual "Already approved?" check ──────────────────────────────────

  Future<void> _handleManualCheck() async {
    if (_isClosing || _isCheckingManually) return;
    setState(() => _isCheckingManually = true);

    try {
      // Check both: in-memory state and WalletConnect SDK sessions
      if (Web3Service.instance.isConnected) {
        _safePop(true);
        return;
      }

      // Give the SDK a brief moment to propagate the session if the event
      // fired just before the user tapped the button
      await Future.delayed(const Duration(milliseconds: 600));

      if (Web3Service.instance.isConnected) {
        _safePop(true);
        return;
      }

      // Not yet connected — start a fresh polling burst (15 s)
      // so the user doesn't have to tap repeatedly
      _startResumePolling(durationSeconds: 15);
    } finally {
      if (mounted && !_isClosing) setState(() => _isCheckingManually = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 5,
              ),
              AppShadows.soft.first,
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // MetaMask Icon / Illustration
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  boxShadow: AppShadows.glowPrimary,
                ),
                child: Image.asset(
                  'assets/images/metamask_fox.png',
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.account_balance_wallet, size: 36, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                widget.title,
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                widget.message,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // ── Connect Button ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _handleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    elevation: 0,
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Connect Wallet',
                              style: AppTextStyles.labelLarge
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // ── "Already approved?" manual check ────────────────────
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed:
                      (_isCheckingManually || _isClosing) ? null : _handleManualCheck,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  icon: _isCheckingManually
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(
                    'Already approved? Tap here',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Cancel Button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => _safePop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Cancel', style: AppTextStyles.labelLarge),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
