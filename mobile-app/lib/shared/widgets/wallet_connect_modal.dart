import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  manual,       // user is entering address manually
  timeout,      // timeout after 30s
}

class _WalletConnectModalState extends State<WalletConnectModal>
    with WidgetsBindingObserver {
  _ConnState _state = _ConnState.idle;
  bool _isClosing = false;
  String _selectedWallet = 'metamask';

  // Manual address entry
  final _manualAddressController = TextEditingController();
  String? _manualAddressError;

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
    WalletConnectService.instance.stopWalletConnectService();
    _manualAddressController.dispose();
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
    WalletConnectService.instance.stopWalletConnectService();
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
  void _startPoller({int maxSeconds = 30}) {
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
        if (kDebugMode) {
          debugPrint('[LOGIN] SESSION_FOUND');
          debugPrint('[LOGIN] SESSION_RESTORED');
          debugPrint('[T2] Session Restored');
        }
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

      // Stop polling and show timeout failsafe after max time
      if (ticks >= maxTicks) {
        timer.cancel();
        WalletConnectService.instance.stopWalletConnectService();
        if (mounted && !_isClosing) {
          setState(() => _state = _ConnState.timeout);
        }
      }
    });
  }

  // ── Finalise connection into Web3Service ──────────────────────────────────

  Future<void> _finaliseConnection() async {
    try {
      if (mounted && !_isClosing) setState(() => _state = _ConnState.checking);
      
      await Future.delayed(const Duration(milliseconds: 800));
      
      // If Web3Service already has the connection, we're done
      if (Web3Service.instance.isConnected) { _safePop(true); return; }

      // WalletConnect has a session — use restoreSession: true so that
      // connectMobileWallet picks up the EXISTING session instead of
      // generating a new URI and re-opening MetaMask (which causes the loop).
      final bool wcHasSession = WalletConnectService.instance.isConnected;
      if (kDebugMode) {
        debugPrint('[LOGIN] _finaliseConnection: wcHasSession=$wcHasSession');
      }

      final ok = await Web3Service.instance
          .connectWallet(
            walletName: _selectedWallet,
            restoreSession: wcHasSession, // true → picks up existing session
          )
          .timeout(const Duration(seconds: 15));
          
      if (ok && mounted && !_isClosing) {
        _safePop(true);
      } else {
        if (mounted && !_isClosing) {
          setState(() => _state = _ConnState.timeout);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection failed or timed out. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted && !_isClosing) {
        setState(() => _state = _ConnState.timeout);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection error. Please make sure you approved in MetaMask.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted && !_isClosing && _state == _ConnState.checking) {
        setState(() => _state = _ConnState.timeout);
      }
    }
  }

  // ── AppLifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_state == _ConnState.waiting || _state == _ConnState.launching)) {
      if (kDebugMode) debugPrint('[LOGIN] APP_RESUMED');
      // User returned from MetaMask — do an immediate check then fast-poll 20 s
      _doImmediateCheckOnResume();
    } else if (state == AppLifecycleState.paused) {
      if (kDebugMode) debugPrint('[LOGIN] APP_PAUSED');
      // App went to background — stop polling (MetaMask is in foreground now)
      _cancelPoller();
    }
  }

  Future<void> _doImmediateCheckOnResume() async {
    if (!mounted || _isClosing) return;

    // Force reconnect relay client in case the OS dropped the websocket in the background
    try {
      final web3App = WalletConnectService.instance.web3App;
      if (web3App != null) {
        if (kDebugMode) debugPrint('[RELAY] RECONNECT_START');
        await web3App.core.relayClient.connect().timeout(const Duration(seconds: 5), onTimeout: () {});
        // Wait until relay is actually connected, max 5s
        int waitMs = 0;
        while (waitMs < 5000) {
          if (web3App.core.relayClient.isConnected) break;
          await Future.delayed(const Duration(milliseconds: 300));
          waitMs += 300;
        }
        if (kDebugMode) debugPrint('[RELAY] isConnected=${web3App.core.relayClient.isConnected} after ${waitMs}ms');
        if (kDebugMode) debugPrint('[RELAY] RECONNECT_SUCCESS');
      }
    } catch (_) {
      // Ignore if already connected or error
    }

    await Future.delayed(const Duration(seconds: 2));

    // Force propagate session from WalletConnect into Web3Service
    try {
      final wcs = WalletConnectService.instance;
      if (wcs.web3App != null) {
        final liveSessions = wcs.web3App!.sessions.getAll();
        if (liveSessions.isNotEmpty) {
          await wcs.forceApplySession(liveSessions.last, walletName: _selectedWallet);
          await Future.delayed(const Duration(seconds: 1));
          
          // WalletConnect now has the session — immediately propagate to Web3Service
          // so that Web3Service.isConnected becomes true before any further checks
          if (wcs.isConnected && !Web3Service.instance.isConnected) {
            if (kDebugMode) debugPrint('[LOGIN] WC has session but Web3Service does not — propagating via connectWallet(restoreSession: true)');
            final ok = await Web3Service.instance
                .connectWallet(walletName: _selectedWallet, restoreSession: true)
                .timeout(const Duration(seconds: 10), onTimeout: () => false);
            if (ok && mounted && !_isClosing) {
              _safePop(true);
              return;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN] forceApplySession error on resume: $e');
    }

    if (mounted && !_isClosing && _state != _ConnState.idle) { _startPoller(maxSeconds: 30); }

    // Immediate synchronous check
    if (Web3Service.instance.isConnected) {
      _safePop(true);
      return;
    }

    final found = await WalletConnectService.instance
        .checkForNewSession(walletName: _selectedWallet);
    if (found) {
      if (kDebugMode) {
        debugPrint('[LOGIN] SESSION_FOUND');
        debugPrint('[LOGIN] SESSION_RESTORED');
        debugPrint('[T2] Session Restored');
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted || _isClosing) return;
      if (Web3Service.instance.isConnected) {
        _safePop(true);
        return;
      }
      await _finaliseConnection();
      return;
    }

    // Not connected yet — start aggressive 30 s polling after resume
    if (mounted && !_isClosing) {
      setState(() => _state = _ConnState.waiting);
      _startPoller(maxSeconds: 30);
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
      // If we are on Web, on a Mobile Device, and NOT in a dApp browser (MetaMask not installed)
      if (kIsWeb && Web3Service.instance.isMobileDevice && !Web3Service.instance.isMetaMaskInstalled) {
        if (kDebugMode) debugPrint('[LOGIN] Web Mobile: Redirecting to MetaMask dApp browser');
        // This will redirect the current page to metamask.app.link/dapp/...
        await Web3Service.instance.connectMobileWallet(walletName: wallet);
        return; // Stop execution here since the page will redirect
      }

      // Step 2: Generate WC URI
      final wcUri = await WalletConnectService.instance.generateConnectionUri();
      if (wcUri == null || !mounted || _isClosing) {
        setState(() => _state = _ConnState.idle);
        return;
      }

      await WalletConnectService.instance.startWalletConnectService();

      // Step 3: Open MetaMask (fire-and-forget — no await on approval)
      await WalletConnectService.instance.launchWalletApp(wcUri, walletName: wallet);

      if (!mounted || _isClosing) return;
      setState(() => _state = _ConnState.waiting);

      // Step 4: Start polling — completely independent of deep-link callback
      _startPoller(maxSeconds: 30);
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

      // Paksa bangunkan WebSocket (RelayClient) sebelum mengecek session
      // Sangat penting untuk OS seperti Xiaomi HyperOS yang memutus jaringan di background
      try {
        final web3App = WalletConnectService.instance.web3App;
        if (web3App != null) {
          if (kDebugMode) debugPrint('[RELAY] MANUAL_CHECK_RECONNECT_START');
          await web3App.core.relayClient.connect();
          if (kDebugMode) debugPrint('[RELAY] MANUAL_CHECK_RECONNECT_SUCCESS');
        }
      } catch (_) {
        // Abaikan error jika sudah terkoneksi
      }

      // Beri jeda 1.5 detik agar WebSocket selesai mendownload session dari server
      await Future.delayed(const Duration(milliseconds: 1500));

      final found = await WalletConnectService.instance
          .checkForNewSession(walletName: _selectedWallet);

      if (!mounted || _isClosing) return;

      if (found) {
        if (kDebugMode) {
          debugPrint('[LOGIN] SESSION_FOUND');
          debugPrint('[LOGIN] SESSION_RESTORED');
          debugPrint('[T2] Session Restored');
        }
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
          _startPoller(maxSeconds: 30);
        }
      }
    } catch (_) {
      if (mounted && !_isClosing) setState(() => _state = _ConnState.waiting);
    }
  }

  // ── Manual address entry ──────────────────────────────────────────────────

  void _showManualInput() {
    if (_isClosing) return;
    _cancelPoller();
    _manualAddressController.clear();
    setState(() {
      _state = _ConnState.manual;
      _manualAddressError = null;
    });
  }

  Future<void> _submitManualAddress() async {
    final address = _manualAddressController.text.trim();

    // Validate Ethereum address format
    if (!address.startsWith('0x') || address.length != 42) {
      setState(() {
        _manualAddressError = 'Invalid address. Must start with 0x and be 42 characters long.';
      });
      return;
    }

    setState(() {
      _state = _ConnState.checking;
      _manualAddressError = null;
    });

    try {
      if (kDebugMode) debugPrint('[LOGIN] MANUAL_ADDRESS_SUBMIT: $address');
      // Cast to dynamic — setManualWalletAddress is only on the mobile implementation
      await (Web3Service.instance as dynamic).setManualWalletAddress(address);
      if (mounted && !_isClosing) _safePop(true);
    } catch (e) {
      if (kDebugMode) debugPrint('[LOGIN] MANUAL_ADDRESS_ERROR: $e');
      if (mounted && !_isClosing) {
        setState(() {
          _state = _ConnState.manual;
          _manualAddressError = 'Failed to connect. Please try again.';
        });
      }
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
      case _ConnState.manual:
        text = 'Enter your wallet address manually as a fallback.';
        break;
      case _ConnState.timeout:
        text = 'Koneksi membutuhkan waktu lebih lama dari biasanya';
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
          TextButton.icon(
            onPressed: _showManualInput,
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text('Enter Address Manually'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              textStyle: AppTextStyles.labelSmall,
            ),
          ),
          const SizedBox(height: 4),
          _CancelButton(onPressed: () => _safePop(false)),
        ];

      // ── Timeout: show Try Again + Batal ────────────────────────────────
      case _ConnState.timeout:
        return [
          _SecondaryButton(
            label: 'Try Again',
            icon: Icons.refresh,
            isLoading: false,
            onPressed: _tryAgain,
          ),
          const SizedBox(height: 10),
          _CancelButton(label: 'Cancel', onPressed: () => _safePop(false)),
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
          _SecondaryButton(
            label: 'Try Again',
            icon: Icons.refresh,
            isLoading: false,
            onPressed: _tryAgain,
          ),
          const SizedBox(height: 10),
          _CancelButton(onPressed: () => _safePop(false)),
        ];

      // ── Manual: show text field + connect button ──────────────────────
      case _ConnState.manual:
        return [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _manualAddressController,
                style: AppTextStyles.bodySmall.copyWith(fontFamily: 'monospace'),
                keyboardType: TextInputType.text,
                inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                decoration: InputDecoration(
                  hintText: 'Paste your wallet address (0x...)',
                  hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: AppColors.surfaceLight.withValues(alpha: 0.3),
                  errorText: _manualAddressError,
                  errorMaxLines: 2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste, size: 18, color: AppColors.textSecondary),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _manualAddressController.text = data!.text!.trim();
                      }
                    },
                  ),
                ),
                onSubmitted: (_) => _submitManualAddress(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PrimaryButton(
            label: 'Connect with This Address',
            icon: Icons.link,
            onPressed: _submitManualAddress,
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'Back to MetaMask',
            icon: Icons.arrow_back,
            isLoading: false,
            onPressed: () => setState(() {
              _state = _ConnState.idle;
              _manualAddressError = null;
            }),
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
  final String label;
  const _CancelButton({required this.onPressed, this.label = 'Cancel'});

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
        child: Text(label, style: AppTextStyles.labelLarge),
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
