import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/core/theme/app_colors.dart';
import 'package:nft_logo_marketplace/core/theme/app_text_styles.dart';
import 'package:nft_logo_marketplace/core/theme/app_radius.dart';
import 'package:nft_logo_marketplace/core/theme/app_shadows.dart';
import 'package:nft_logo_marketplace/core/services/web3_service.dart';
import 'package:nft_logo_marketplace/core/services/walletconnect_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WalletConnectModal
//
// Connection flow (works on ALL Android brands without deep-link callbacks):
//   1. User taps "Connect Wallet" → picks wallet from bottom sheet
//   2. Modal generates WC URI via WalletConnectService.generateConnectionUri()
//   3. MetaMask is opened with the URI via launchWalletApp()
//   4. A 500 ms poller calls checkForNewSession() — no deep-link dependency
//   5. On AppLifecycleState.resumed (user returns from MetaMask), an
//      extra immediate check + 60 s fast-poll is started
//   6. "Already Approved ✓" button triggers an instant manual check
//   7. "Try Again" restarts the entire flow from scratch
//   8. Auto-closes modal silently when connection is confirmed
// ─────────────────────────────────────────────────────────────────────────────

class WalletConnectModal extends StatefulWidget {
  final String title;
  final String message;

  const WalletConnectModal({
    super.key,
    this.title = 'Connect Wallet Required',
    this.message = 'Please connect your wallet to participate in the marketplace.',
  });

  static bool _isDialogOpen = false;

  static Future<bool> show(
    BuildContext context, {
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
        pageBuilder: (ctx, anim, _) =>
            WalletConnectModal(title: title, message: message),
        transitionBuilder: (ctx, anim, _, child) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        ),
      );
      return result ?? false;
    } finally {
      _isDialogOpen = false;
    }
  }

  @override
  State<WalletConnectModal> createState() => _WalletConnectModalState();
}

// ─── Connection state machine ─────────────────────────────────────────────────

enum _ConnState {
  idle,          // initial — waiting for user to tap "Connect Wallet"
  launching,    // generating URI + opening MetaMask
  waiting,      // MetaMask is open, polling for session
  checking,     // manual "Already Approved" check in progress
}

class _WalletConnectModalState extends State<WalletConnectModal>
    with WidgetsBindingObserver {
  _ConnState _state = _ConnState.idle;
  bool _isClosing = false;
  String _selectedWallet = 'metamask';

  // Polling timer — 500 ms ticks
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen for connection state changes from WalletConnectService
    WalletConnectService.instance.addListener(_onWcChanged);
    Web3Service.instance.addListener(_onWeb3Changed);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && Web3Service.instance.isConnected) _safePop(true);
    });
  }

  @override
  void dispose() {
    _cancelPoller();
    WidgetsBinding.instance.removeObserver(this);
    WalletConnectService.instance.removeListener(_onWcChanged);
    Web3Service.instance.removeListener(_onWeb3Changed);
    super.dispose();
  }

  // ── Safe close ────────────────────────────────────────────────────────────

  void _safePop(bool result) {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    _cancelPoller();
    Navigator.of(context).pop(result);
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _cancelPoller() {
    _poller?.cancel();
    _poller = null;
  }

  /// Starts a 500 ms poller for [maxSeconds].
  /// Calls [WalletConnectService.checkForNewSession] on every tick.
  /// Silently auto-closes modal if a session is found.
  void _startPoller({int maxSeconds = 180}) {
    _cancelPoller();
    int ticks = 0;
    final maxTicks = maxSeconds * 2; // 500 ms per tick

    _poller = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      ticks++;
      if (!mounted || _isClosing) {
        timer.cancel();
        return;
      }

      // Check Web3Service first (covers event-driven path)
      if (Web3Service.instance.isConnected) {
        timer.cancel();
        _safePop(true);
        return;
      }

      // Poll WalletConnect SDK sessions directly — no deep link needed
      final found = await WalletConnectService.instance
          .checkForNewSession(walletName: _selectedWallet);

      if (found) {
        timer.cancel();
        // WalletConnectService.checkForNewSession() calls notifyListeners()
        // which triggers _onWcChanged / connectMobileWallet completion.
        // Give Web3Service 800 ms to propagate the new session into its state.
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_isClosing) {
          if (Web3Service.instance.isConnected) {
            _safePop(true);
          } else {
            // Manually trigger the complete flow via Web3Service
            await _finaliseConnection();
          }
        }
        return;
      }

      // Stop polling silently after max time
      if (ticks >= maxTicks) {
        timer.cancel();
        if (mounted && !_isClosing) {
          setState(() => _state = _ConnState.idle);
        }
      }
    });
  }

  // ── Finalise connection into Web3Service ──────────────────────────────────

  /// Called when WalletConnectService has a session but Web3Service hasn't
  /// picked it up yet (event-driven path failed on this device).
  /// Delegates to connectWallet(restoreSession:false) which will see the
  /// already-connected WalletConnectService and complete immediately.
  Future<void> _finaliseConnection() async {
    try {
      // WalletConnectService already has the session; connectMobileWallet
      // checks _walletConnect.isConnected and short-circuits to state update.
      final ok = await Web3Service.instance
          .connectWallet(walletName: _selectedWallet, restoreSession: false)
          .timeout(const Duration(seconds: 10));
      if (ok && mounted && !_isClosing) _safePop(true);
    } catch (_) {
      // Silent — polling will retry
    }
  }

  // ── AppLifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_state == _ConnState.waiting || _state == _ConnState.launching)) {
      // User returned from MetaMask — do an immediate check then fast-poll 60 s
      _doImmediateCheckOnResume();
    } else if (state == AppLifecycleState.paused) {
      // App went to background — stop polling (MetaMask is in foreground now)
      _cancelPoller();
    }
  }

  Future<void> _doImmediateCheckOnResume() async {
    if (!mounted || _isClosing) return;

    // Immediate synchronous check
    if (Web3Service.instance.isConnected) {
      _safePop(true);
      return;
    }

    final found = await WalletConnectService.instance
        .checkForNewSession(walletName: _selectedWallet);
    if (found) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || _isClosing) return;
      if (Web3Service.instance.isConnected) {
        _safePop(true);
        return;
      }
      await _finaliseConnection();
      return;
    }

    // Not connected yet — start aggressive 60 s polling after resume
    if (mounted && !_isClosing) {
      setState(() => _state = _ConnState.waiting);
      _startPoller(maxSeconds: 60);
    }
  }

  // ── Listeners ─────────────────────────────────────────────────────────────

  void _onWcChanged() {
    if (!mounted || _isClosing) return;
    if (WalletConnectService.instance.isConnected) {
      // WalletConnectService got a session — try to propagate to Web3Service
      _finaliseConnection();
    }
  }

  void _onWeb3Changed() {
    if (!mounted || _isClosing) return;
    if (Web3Service.instance.isConnected) {
      _cancelPoller();
      if (mounted && !_isClosing) setState(() => _state = _ConnState.idle);
      _safePop(true);
    }
  }

  // ── Wallet picker + connect flow ──────────────────────────────────────────

  Future<void> _startConnectFlow() async {
    if (_state != _ConnState.idle || _isClosing) return;
    if (Web3Service.instance.isConnected) { _safePop(true); return; }

    // Step 1: Pick wallet
    final wallet = await _showWalletPicker();
    if (wallet == null || !mounted || _isClosing) return;
    _selectedWallet = wallet;

    setState(() => _state = _ConnState.launching);

    try {
      // Step 2: Generate WC URI
      final wcUri = await WalletConnectService.instance.generateConnectionUri();
      if (wcUri == null || !mounted || _isClosing) {
        setState(() => _state = _ConnState.idle);
        return;
      }

      // Step 3: Open MetaMask (fire-and-forget — no await on approval)
      await WalletConnectService.instance.launchWalletApp(wcUri, walletName: wallet);

      if (!mounted || _isClosing) return;
      setState(() => _state = _ConnState.waiting);

      // Step 4: Start polling — completely independent of deep-link callback
      _startPoller(maxSeconds: 180);
    } catch (_) {
      if (mounted && !_isClosing) setState(() => _state = _ConnState.idle);
    }
  }

  /// Try Again: cancel everything and restart from URI generation.
  Future<void> _tryAgain() async {
    if (_isClosing) return;
    _cancelPoller();
    setState(() => _state = _ConnState.idle);
    // Brief pause so user can see the reset, then restart
    await Future.delayed(const Duration(milliseconds: 200));
    _startConnectFlow();
  }

  /// "Already Approved ✓" manual check.
  Future<void> _manualCheck() async {
    if (_state == _ConnState.checking || _isClosing) return;
    setState(() => _state = _ConnState.checking);

    try {
      if (Web3Service.instance.isConnected) { _safePop(true); return; }

      final found = await WalletConnectService.instance
          .checkForNewSession(walletName: _selectedWallet);

      if (!mounted || _isClosing) return;

      if (found) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted || _isClosing) return;
        if (Web3Service.instance.isConnected) {
          _safePop(true);
        } else {
          await _finaliseConnection();
        }
      } else {
        // Not found — quietly go back to waiting + restart poller
        if (mounted && !_isClosing) {
          setState(() => _state = _ConnState.waiting);
          _startPoller(maxSeconds: 60);
        }
      }
    } catch (_) {
      if (mounted && !_isClosing) setState(() => _state = _ConnState.waiting);
    }
  }

  // ── Wallet picker bottom sheet ────────────────────────────────────────────

  Future<String?> _showWalletPicker() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WalletPickerSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
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
              // ── Icon ─────────────────────────────────────────────────
              _buildIcon(),
              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────────────────
              Text(
                widget.title,
                style: AppTextStyles.h3.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              // ── Status / message ─────────────────────────────────────
              _buildStatusText(),
              const SizedBox(height: 28),

              // ── Buttons ──────────────────────────────────────────────
              ..._buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.card,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        boxShadow: AppShadows.glowPrimary,
      ),
      child: _state == _ConnState.waiting || _state == _ConnState.launching
          ? const CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            )
          : Image.asset(
              'assets/images/metamask_fox.png',
              errorBuilder: (_, __, ___) => const Icon(
                Icons.account_balance_wallet,
                size: 36,
                color: AppColors.primary,
              ),
            ),
    );
  }

  Widget _buildStatusText() {
    final String text;
    switch (_state) {
      case _ConnState.launching:
        text = 'Opening MetaMask…\nPlease approve the connection request.';
        break;
      case _ConnState.waiting:
        text = 'Waiting for MetaMask approval…\nSwitch to MetaMask and approve, then return here.';
        break;
      case _ConnState.checking:
        text = 'Checking connection status…';
        break;
      case _ConnState.idle:
        text = widget.message;
    }
    return Text(
      text,
      style: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textSecondary,
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  List<Widget> _buildButtons() {
    switch (_state) {
      // ── Idle: show Connect button ──────────────────────────────────────
      case _ConnState.idle:
        return [
          _PrimaryButton(
            label: 'Connect Wallet',
            icon: Icons.account_balance_wallet,
            onPressed: _startConnectFlow,
          ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => _safePop(false)),
        ];

      // ── Launching / Waiting: show Already Approved + Try Again ─────────
      case _ConnState.launching:
      case _ConnState.waiting:
        return [
          _SecondaryButton(
            label: 'Already Approved ✓',
            icon: Icons.check_circle_outline,
            isLoading: false,
            onPressed: _manualCheck,
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'Try Again',
            icon: Icons.refresh,
            isLoading: false,
            onPressed: _tryAgain,
          ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => _safePop(false)),
        ];

      // ── Checking: show spinner ─────────────────────────────────────────
      case _ConnState.checking:
        return [
          _SecondaryButton(
            label: 'Checking…',
            icon: Icons.check_circle_outline,
            isLoading: true,
            onPressed: null,
          ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => _safePop(false)),
        ];
    }
  }
}

// ─── Reusable button widgets ──────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.primary,
                ),
              )
            : Icon(icon, size: 16),
        label: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CancelButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        child: const Text('Cancel', style: AppTextStyles.labelLarge),
      ),
    );
  }
}

// ─── Wallet picker sheet ──────────────────────────────────────────────────────

class _WalletPickerSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Wallet',
            style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Select your preferred wallet to connect',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          _walletTile(context, 'MetaMask', 'metamask',
              Icons.account_balance_wallet_outlined, const Color(0xFFE17726)),
          _walletTile(context, 'Trust Wallet', 'trust',
              Icons.security, const Color(0xFF3375BB)),
          _walletTile(context, 'Rainbow', 'rainbow',
              Icons.palette_outlined, const Color(0xFF7C4DFF)),
          const Divider(height: 24),
          _walletTile(context, 'Other Wallets', 'other',
              Icons.more_horiz, AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _walletTile(BuildContext context, String name, String id,
      IconData icon, Color color) {
    return ListTile(
      onTap: () => Navigator.pop(context, id),
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(name,
          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
    );
  }
}
