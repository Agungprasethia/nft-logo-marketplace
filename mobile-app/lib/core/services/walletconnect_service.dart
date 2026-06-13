// WalletConnect Service for MetaMask Mobile Integration
// Uses WalletConnect v2 protocol with project ID
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:nft_logo_marketplace/config/contract_config.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart' as app_session;

class WalletConnectService extends ChangeNotifier with WidgetsBindingObserver {
  static WalletConnectService? _instance;
  static WalletConnectService get instance => _instance ??= WalletConnectService._();

  WalletConnectService._();

  Web3App? _web3App;
  SessionData? _session;
  String? _connectedAddress;
  int? _chainId;

  // Pending connect response kept for callers that want to race
  ConnectResponse? _pendingConnect;

  bool get isConnected => _session != null && _connectedAddress != null;
  String? get address => _connectedAddress;
  int? get chainId => _chainId;
  bool get isOnSepolia => _chainId == ContractConfig.chainId;
  bool get isInitialized => _web3App != null;
  Web3App? get web3App => _web3App;

  // ── Initialization ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_web3App != null) return;

    WidgetsBinding.instance.addObserver(this);

    _web3App = await Web3App.createInstance(
      projectId: ContractConfig.walletConnectProjectId,
      metadata: const PairingMetadata(
        name: 'L E O',
        description: 'Marketplace for Logo NFT with Copyright',
        url: 'https://nft-logo-marketplace.app',
        icons: ['https://upload.wikimedia.org/wikipedia/commons/3/36/MetaMask_Fox.svg'],
        redirect: Redirect(
          native: 'nftlogomarketplace://',
          universal: 'https://nft-logo-marketplace.app',
        ),
      ),
    );

    // Listen for session lifecycle events
    _web3App!.onSessionConnect.subscribe(_onSessionConnect);
    _web3App!.onSessionDelete.subscribe(_onSessionDelete);
    _web3App!.onSessionExpire.subscribe(_onSessionExpire);
    _web3App!.onSessionUpdate.subscribe(_onSessionUpdate);
    _web3App!.onSessionEvent.subscribe(_onSessionEvent);

    // Restore existing sessions
    final sessions = _web3App!.sessions.getAll();
    if (sessions.isNotEmpty) {
      final savedSession = await app_session.SessionService.instance.getSession();
      if (savedSession != null) {
        try {
          _session = sessions.firstWhere((s) => s.topic == savedSession.sessionTopic);
          _extractAddressFromSession();

          if (_chainId != ContractConfig.chainId) {
            if (kDebugMode) debugPrint('⚠️ Restored session on wrong network (Chain $_chainId). Clearing...');
            await app_session.SessionService.instance.clearSession();
            _session = null;
            _connectedAddress = null;
            _chainId = null;
          } else {
            if (kDebugMode) debugPrint('✅ WalletConnect session restored on correct network');
          }
        } catch (_) {
          if (kDebugMode) debugPrint('⚠️ Stored session topic not found. Clearing...');
          await app_session.SessionService.instance.clearSession();
          _session = null;
        }
      } else {
        // WalletConnect session exists but no app session — disconnect stale sessions
        if (kDebugMode) debugPrint('⚠️ WalletConnect sessions exist without app session. Clearing stale sessions...');
        for (final s in sessions) {
          try {
            await _web3App!.disconnectSession(
              topic: s.topic,
              reason: const WalletConnectError(code: 0, message: 'User disconnected'),
            );
          } catch (_) {}
        }
        _session = null;
      }
    } else {
      await app_session.SessionService.instance.clearSession();
    }

    if (kDebugMode) debugPrint('[LOGIN] WALLETCONNECT_INITIALIZED');
  }

  // ── Session event handlers ──────────────────────────────────────────────

  void _onSessionConnect(SessionConnect? event) {
    if (event?.session != null) {
      _session = event!.session;
      _extractAddressFromSession();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('✅ [EVENT] Session connected: $_connectedAddress');
        debugPrint('[LOGIN] SESSION_APPROVED');
        debugPrint('[LOGIN] SESSION_RECEIVED');
      }
    }
  }

  void _onSessionDelete(SessionDelete? event) async {
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
    if (kDebugMode) debugPrint('🔌 Session deleted by wallet');
  }

  void _onSessionExpire(SessionExpire? event) async {
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
    if (kDebugMode) debugPrint('🔌 Session expired');
  }

  void _onSessionUpdate(SessionUpdate? event) {
    if (event?.namespaces != null) {
      _extractAddressFromSession();
      notifyListeners();
      if (kDebugMode) debugPrint('🔄 Session updated');
    }
  }

  void _onSessionEvent(SessionEvent? event) {
    if (event?.name == 'chainChanged' || event?.name == 'accountsChanged') {
      _extractAddressFromSession();
      notifyListeners();
      if (kDebugMode) debugPrint('🔄 Session event: ${event?.name}');
    }
  }

  // ── Address extraction ──────────────────────────────────────────────────

  void _extractAddressFromSession() {
    if (_session == null) return;
    final namespaces = _session!.namespaces;
    if (namespaces.containsKey('eip155')) {
      final accounts = namespaces['eip155']!.accounts;
      if (accounts.isNotEmpty) {
        // Format: eip155:<chainId>:<address>
        final parts = accounts.first.split(':');
        if (parts.length >= 3) {
          _chainId = int.tryParse(parts[1]);
          _connectedAddress = parts[2];
          if (kDebugMode) debugPrint('[LOGIN] WALLET_ADDRESS_RECEIVED');
          if (kDebugMode) debugPrint('[T3] Wallet Address Received: $_connectedAddress');
        }
      }
    }
  }

  // ── URI Generation (Step 1 of new flow) ────────────────────────────────

  /// Generates a WalletConnect URI and saves the pending connect response.
  /// Call this ONCE, then open MetaMask manually, then poll [checkForNewSession].
  ///
  /// Returns the raw WC URI string, or null if Web3App is not ready.
  Future<Uri?> generateConnectionUri() async {
    if (_web3App == null) await initialize();

    // Cancel any previous pending connect
    _pendingConnect = null;

    final connectResponse = await _web3App!.connect(
      optionalNamespaces: {
        'eip155': RequiredNamespace(
          chains: ['eip155:${ContractConfig.chainId}'],
          methods: [
            'eth_sendTransaction',
            'eth_signTransaction',
            'eth_sign',
            'personal_sign',
            'eth_signTypedData',
          ],
          events: ['chainChanged', 'accountsChanged'],
        ),
      },
    );

    _pendingConnect = connectResponse;
    final uri = connectResponse.uri;
    if (uri != null) {
      if (kDebugMode) debugPrint('🔗 WC URI generated: $uri');
    }
    return uri;
  }

  // ── Open wallet app (Step 2 of new flow) ────────────────────────────────

  /// Opens the wallet app with the given WC URI.
  /// Tries native deep link first, falls back to universal link.
  Future<void> launchWalletApp(Uri wcUri, {String walletName = 'metamask'}) async {
    final encoded = Uri.encodeComponent(wcUri.toString());
    Uri appUri;
    Uri fallbackUri;

    switch (walletName) {
      case 'trust':
        appUri = Uri.parse('trust://wc?uri=$encoded');
        fallbackUri = Uri.parse('https://link.trustwallet.com/wc?uri=$encoded');
        break;
      case 'safe':
        appUri = Uri.parse('safe://wc?uri=$encoded');
        fallbackUri = Uri.parse('https://app.safe.global/wc?uri=$encoded');
        break;
      case 'rainbow':
        appUri = Uri.parse('rainbow://wc?uri=$encoded');
        fallbackUri = Uri.parse('https://rainbow.me/wc?uri=$encoded');
        break;
      case 'other':
        appUri = wcUri;
        fallbackUri = wcUri;
        break;
      default: // metamask
        appUri = Uri.parse('metamask://wc?uri=$encoded');
        fallbackUri = Uri.parse('https://metamask.app.link/wc?uri=$encoded');
    }

    bool launched = false;
    try {
      if (await canLaunchUrl(appUri)) {
        if (kDebugMode) {
          debugPrint('🚀 Launching $walletName via deep link...');
          debugPrint('[LOGIN] OPENING_METAMASK');
        }
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        launched = true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Deep link launch failed: $e');
    }

    if (!launched) {
      if (kDebugMode) debugPrint('🌐 Fallback to universal link...');
      try {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Universal link launch also failed: $e');
      }
    }
  }

  // ── Session check (Step 3 of new flow — poll this from UI) ─────────────

  /// Checks if a new session has appeared in `sessions.getAll()` after
  /// calling [generateConnectionUri]. If yes, promotes it to app state.
  ///
  /// Returns true if a valid session was found and applied.
  /// This is designed to be called repeatedly (every 500 ms) from the UI layer.
  Future<bool> checkForNewSession({String walletName = 'metamask'}) async {
    if (_web3App == null) return false;

    // Already connected — nothing to do
    if (isConnected) return true;

    final liveSessions = _web3App!.sessions.getAll();
    if (liveSessions.isEmpty) {
      // Also check _session in case the event fired but getAll() is stale
      if (_session != null) {
        _extractAddressFromSession();
        if (_connectedAddress != null) {
          await _persistSession(walletName);
          notifyListeners();
          return true;
        }
      }
      return false;
    }

    // Found a live session — promote it
    final newSession = liveSessions.last;
    if (kDebugMode) debugPrint('✅ [POLL] New session found: ${newSession.topic}');
    await forceApplySession(newSession, walletName: walletName);
    return true;
  }

  /// Manually promotes a [SessionData] into the service state.
  /// Use when you have a session from `sessions.getAll()` but the
  /// onSessionConnect event never fired.
  Future<void> forceApplySession(SessionData session, {String walletName = 'metamask'}) async {
    _session = session;
    _extractAddressFromSession();

    if (_connectedAddress != null) {
      if (kDebugMode) debugPrint('✅ [FORCE] Session applied: $_connectedAddress on chain $_chainId');
      await _persistSession(walletName);
      notifyListeners();
    } else {
      if (kDebugMode) debugPrint('⚠️ [FORCE] Session found but address extraction failed');
    }
  }

  Future<void> _persistSession(String walletName) async {
    if (_connectedAddress == null || _chainId == null || _session == null) return;
    try {
      await app_session.SessionService.instance.saveSession(
        app_session.SessionData(
          walletAddress: _connectedAddress!,
          walletProvider: walletName,
          chainId: _chainId!,
          connectedAt: DateTime.now(),
          sessionTopic: _session!.topic,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to persist session: $e');
    }
  }

  // ── Legacy connect() — kept for restore-session path ───────────────────

  /// Full connect flow used only for session RESTORE (no UI interaction needed).
  /// For new connections, use generateConnectionUri() + launchWalletApp() +
  /// checkForNewSession() from the UI layer instead.
  Future<bool> connect({String walletName = 'metamask'}) async {
    if (_web3App == null) await initialize();

    try {
      final wcUri = await generateConnectionUri();
      if (wcUri == null) return false;

      await launchWalletApp(wcUri, walletName: walletName);

      if (kDebugMode) debugPrint('⏳ Polling for session (event + poll, 180 s)...');

      // Race two paths:
      //  A) SDK event fires  →  _session gets set via _onSessionConnect
      //  B) Polling detects session in sessions.getAll()
      SessionData? approvedSession;

      await Future.any([
        // Path A: SDK event
        _pendingConnect!.session.future
            .timeout(const Duration(seconds: 30), onTimeout: () {
              stopWalletConnectService();
              throw TimeoutException('Connection timeout');
            })
            .then((s) { approvedSession = s; })
            .catchError((e) { if (e is! TimeoutException) throw e; }),

        // Path B: Polling every 500 ms for 30 s
        () async {
          for (int i = 0; i < 60; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            final live = _web3App!.sessions.getAll();
            if (live.isNotEmpty) {
              approvedSession = live.last;
              if (kDebugMode) debugPrint('✅ [POLL] Session on attempt $i');
              return;
            }
            if (_session != null) {
              approvedSession = _session;
              if (kDebugMode) debugPrint('✅ [POLL] Event-set session on attempt $i');
              return;
            }
          }
          stopWalletConnectService();
          throw TimeoutException('Connection timeout');
        }(),
      ]);

      if (approvedSession == null) {
        stopWalletConnectService();
        throw Exception('Connection timeout — user did not approve in MetaMask');
      }

      await forceApplySession(approvedSession!, walletName: walletName);
      return isConnected;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ WalletConnect.connect() error: $e');
      rethrow;
    }
  }

  // ── Disconnect ──────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    if (_session != null && _web3App != null) {
      try {
        await _web3App!.disconnectSession(
          topic: _session!.topic,
          reason: const WalletConnectError(code: 0, message: 'User disconnected'),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Error disconnecting WalletConnect session: $e');
      }
    }
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    _pendingConnect = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
  }

  // ── Session validity ────────────────────────────────────────────────────

  Future<bool> _isSessionValid() async {
    if (_session == null || _web3App == null) return false;
    try {
      final sessions = _web3App!.sessions.getAll();
      return sessions.any((s) => s.topic == _session!.topic);
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureConnected() async {
    if (!await _isSessionValid()) {
      if (kDebugMode) debugPrint('⚠️ Session invalid, clearing...');
      _session = null;
      _connectedAddress = null;
      _chainId = null;
      await app_session.SessionService.instance.clearSession();
      notifyListeners();
      throw Exception('Session expired. Please reconnect to MetaMask.');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // CENTRALIZED TRANSACTION HANDLER
  // Gas estimation is handled ENTIRELY by MetaMask — never send gas params.
  // ════════════════════════════════════════════════════════════════════════

  Future<String> sendTransaction({
    required String to,
    required String data,
    String? value,
  }) async {
    if (_session == null || _connectedAddress == null) {
      throw Exception('Wallet not connected');
    }

    await ensureConnected();

    try {
      final txParams = <String, dynamic>{
        'from': _connectedAddress,
        'to': to,
        if (data.isNotEmpty && data != '0x') 'data': data,
        if (value != null) 'value': value,
      };

      // Safety guard: block any accidental gas parameters
      const forbiddenKeys = ['gas', 'gasLimit', 'gasPrice', 'maxFeePerGas', 'maxPriorityFeePerGas'];
      for (final key in forbiddenKeys) {
        if (txParams.containsKey(key)) {
          txParams.remove(key);
          if (kDebugMode) debugPrint('🚫 BLOCKED forbidden gas param: $key');
        }
      }

      if (kDebugMode) {
        debugPrint('╔══════════════════════════════════════════════');
        debugPrint('║ 📤 TX PAYLOAD');
        debugPrint('║ from: ${txParams['from']}');
        debugPrint('║ to:   ${txParams['to']}');
        if (txParams.containsKey('data')) {
          final d = txParams['data'] as String;
          debugPrint('║ data: ${d.length > 10 ? '${d.substring(0, 10)}...' : d}');
        }
        if (txParams.containsKey('value')) debugPrint('║ value: ${txParams['value']}');
        debugPrint('║ gas:  ⛽ MetaMask auto-estimate');
        debugPrint('╚══════════════════════════════════════════════');
      }

      final txFuture = _web3App!.request(
        topic: _session!.topic,
        chainId: 'eip155:${ContractConfig.chainId}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [txParams],
        ),
      );

      await _openMetaMaskForTransaction();

      if (kDebugMode) debugPrint('⏳ Waiting for user approval in MetaMask...');
      final txHash = await txFuture.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw Exception('Transaction request timed out in MetaMask'),
      );

      if (kDebugMode) debugPrint('✅ Transaction approved! Hash: $txHash');
      return txHash.toString();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Transaction failed: $e');
      if (e.toString().contains('session') || e.toString().contains('topic')) {
        _session = null;
        _connectedAddress = null;
        _chainId = null;
        await app_session.SessionService.instance.clearSession();
        notifyListeners();
        throw Exception('Session expired. Please reconnect to MetaMask.');
      }
      rethrow;
    }
  }

  Future<void> _openMetaMaskForTransaction() async {
    try {
      final topic = _session?.topic;
      final walletUri = topic != null
          ? Uri.parse('metamask://wc?topic=$topic')
          : Uri.parse('metamask://');

      if (await canLaunchUrl(walletUri)) {
        if (kDebugMode) debugPrint('🦊 Opening MetaMask for transaction approval...');
        await launchUrl(walletUri, mode: LaunchMode.externalApplication);
      } else {
        final universalUri = topic != null
            ? Uri.parse('https://metamask.app.link/wc?topic=$topic')
            : Uri.parse('https://metamask.app.link/');
        await launchUrl(universalUri, mode: LaunchMode.externalApplication);
      }
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not open MetaMask for tx: $e');
    }
  }

  // ── Balance via RPC ─────────────────────────────────────────────────────

  Future<double> getBalance() async {
    if (_connectedAddress == null) return 0;
    try {
      final response = await http.post(
        Uri.parse(ContractConfig.rpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'eth_getBalance',
          'params': [_connectedAddress, 'latest'],
          'id': 1,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          final balanceWei = BigInt.parse(
            data['result'].toString().replaceFirst('0x', ''),
            radix: 16,
          );
          return balanceWei / BigInt.from(10).pow(18);
        }
      }
      return 0;
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting balance: $e');
      return 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _web3App?.onSessionConnect.unsubscribe(_onSessionConnect);
    _web3App?.onSessionDelete.unsubscribe(_onSessionDelete);
    _web3App?.onSessionExpire.unsubscribe(_onSessionExpire);
    _web3App?.onSessionUpdate.unsubscribe(_onSessionUpdate);
    _web3App?.onSessionEvent.unsubscribe(_onSessionEvent);
    super.dispose();
  }

  // ── Foreground Service ──────────────────────────────────────────────────

  static const MethodChannel _channel = MethodChannel('com.example.nft_logo_marketplace/walletconnect');

  Future<void> startWalletConnectService() async {
    // Foreground service is unnecessary for WalletConnect v2 relays 
    // and causes SecurityException on Android 14+ for connectedDevice type.
    // try {
    //   await _channel.invokeMethod('startService');
    // } catch (e) {
    //   if (kDebugMode) debugPrint('Failed to start Foreground Service: $e');
    // }
  }

  Future<void> stopWalletConnectService() async {
    // try {
    //   await _channel.invokeMethod('stopService');
    // } catch (e) {
    //   if (kDebugMode) debugPrint('Failed to stop Foreground Service: $e');
    // }
  }

  // ── App Lifecycle ───────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_session == null && _pendingConnect != null) {
        if (_web3App != null) {
          try {
            _web3App!.core.relayClient.connect();
          } catch (_) {}
        }
      }
    }
  }
}
