// WalletConnect Service for MetaMask Mobile Integration
// Uses WalletConnect v2 protocol with project ID
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:nft_logo_marketplace/config/contract_config.dart';
import 'package:nft_logo_marketplace/core/services/session_service.dart' as app_session;

class WalletConnectService extends ChangeNotifier {
  static WalletConnectService? _instance;
  static WalletConnectService get instance => _instance ??= WalletConnectService._();
  
  WalletConnectService._();

  Web3App? _web3App;
  SessionData? _session;
  String? _connectedAddress;
  int? _chainId;
  
  bool get isConnected => _session != null && _connectedAddress != null;
  String? get address => _connectedAddress;
  int? get chainId => _chainId;
  bool get isOnSepolia => _chainId == ContractConfig.chainId;
  bool get isInitialized => _web3App != null;
  
  /// Initialize WalletConnect
  Future<void> initialize() async {
    if (_web3App != null) return;
    
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
    
    // Listen for session events
    _web3App!.onSessionConnect.subscribe(_onSessionConnect);
    _web3App!.onSessionDelete.subscribe(_onSessionDelete);
    _web3App!.onSessionExpire.subscribe(_onSessionExpire);
    _web3App!.onSessionUpdate.subscribe(_onSessionUpdate);
    _web3App!.onSessionEvent.subscribe(_onSessionEvent);
    
    // Check for existing sessions securely
    final sessions = _web3App!.sessions.getAll();
    if (sessions.isNotEmpty) {
      final savedSession = await app_session.SessionService.instance.getSession();
      if (savedSession != null) {
        try {
          _session = sessions.firstWhere((s) => s.topic == savedSession.sessionTopic);
          _extractAddressFromSession();
          
          if (_chainId != ContractConfig.chainId) {
            if (kDebugMode) { debugPrint('⚠️ Restored session is on wrong network (Chain $_chainId). Expected ${ContractConfig.chainId}. Clearing...'); }
            await app_session.SessionService.instance.clearSession();
            _session = null;
            _connectedAddress = null;
            _chainId = null;
          } else {
            if (kDebugMode) { debugPrint('✅ WalletConnect session restored securely on correct network'); }
          }
        } catch (e) {
          if (kDebugMode) { debugPrint('⚠️ Stored session topic not found in active WalletConnect sessions'); }
          await app_session.SessionService.instance.clearSession();
          _session = null;
        }
      } else {
        // We have a WalletConnect session but no secure app session.
        // This might happen if the app was uninstalled or secure storage was cleared.
        if (kDebugMode) { debugPrint('⚠️ WalletConnect session exists but no secure session found. Disconnecting...'); }
        for (var s in sessions) {
          await _web3App!.disconnectSession(
            topic: s.topic,
            reason: const WalletConnectError(code: 0, message: 'User disconnected'),
          );
        }
        _session = null;
      }
    } else {
      await app_session.SessionService.instance.clearSession();
    }
    
    if (kDebugMode) { debugPrint('✅ WalletConnect initialized'); }
  }
  
  void _onSessionConnect(SessionConnect? event) {
    if (event?.session != null) {
      _session = event!.session;
      _extractAddressFromSession();
      notifyListeners();
      if (kDebugMode) { debugPrint('✅ Session connected: $_connectedAddress'); }
    }
  }
  
  void _onSessionDelete(SessionDelete? event) async {
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
    if (kDebugMode) { debugPrint('🔌 Session deleted by wallet'); }
  }

  void _onSessionExpire(SessionExpire? event) async {
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
    if (kDebugMode) { debugPrint('🔌 Session expired naturally'); }
  }

  void _onSessionUpdate(SessionUpdate? event) {
    if (event?.namespaces != null) {
      if (kDebugMode) { debugPrint('🔄 Session updated (e.g. account/network change)'); }
      _extractAddressFromSession();
      notifyListeners();
    }
  }

  void _onSessionEvent(SessionEvent? event) {
    if (event?.name == 'chainChanged' || event?.name == 'accountsChanged') {
      if (kDebugMode) { debugPrint('🔄 Session event received: ${event?.name}'); }
      // Trigger a re-extraction of state if needed
      _extractAddressFromSession();
      notifyListeners();
    }
  }
  
  void _extractAddressFromSession() {
    if (_session == null) return;
    
    final namespaces = _session!.namespaces;
    if (namespaces.containsKey('eip155')) {
      final accounts = namespaces['eip155']!.accounts;
      if (accounts.isNotEmpty) {
        // Format: eip155:chainId:address
        final parts = accounts.first.split(':');
        if (parts.length >= 3) {
          _chainId = int.tryParse(parts[1]);
          _connectedAddress = parts[2];
        }
      }
    }
  }
  
  /// Connect via WalletConnect
  Future<bool> connect({String walletName = 'metamask'}) async {
    if (_web3App == null) {
      await initialize();
    }
    
    try {
      // Create connection - Note: cannot use const because of string interpolation
      final connectResponse = await _web3App!.connect(
        requiredNamespaces: {
          'eip155': RequiredNamespace(
            chains: ['eip155:${ContractConfig.chainId}'], // Sepolia 11155111
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
      
      // Get the URI for deep linking
      final uri = connectResponse.uri;
      if (uri != null) {
        if (kDebugMode) { debugPrint('🔗 WalletConnect URI: $uri'); }
        
        // Open specific wallet with the WalletConnect URI
        Uri appUri;
        Uri fallbackUri;

        if (walletName == 'trust') {
          appUri = Uri.parse('trust://wc?uri=${Uri.encodeComponent(uri.toString())}');
          fallbackUri = Uri.parse('https://link.trustwallet.com/wc?uri=${Uri.encodeComponent(uri.toString())}');
        } else if (walletName == 'safe') {
          appUri = Uri.parse('safe://wc?uri=${Uri.encodeComponent(uri.toString())}');
          fallbackUri = Uri.parse('https://app.safe.global/wc?uri=${Uri.encodeComponent(uri.toString())}');
        } else if (walletName == 'rainbow') {
          appUri = Uri.parse('rainbow://wc?uri=${Uri.encodeComponent(uri.toString())}');
          fallbackUri = Uri.parse('https://rainbow.me/wc?uri=${Uri.encodeComponent(uri.toString())}');
        } else if (walletName == 'other') {
          // Keep it generic to show app chooser
          appUri = Uri.parse(uri.toString());
          fallbackUri = appUri;
        } else {
          // Default: MetaMask
          appUri = Uri.parse('metamask://wc?uri=${Uri.encodeComponent(uri.toString())}');
          fallbackUri = Uri.parse('https://metamask.app.link/wc?uri=${Uri.encodeComponent(uri.toString())}');
        }

        if (await canLaunchUrl(appUri)) {
          if (kDebugMode) { debugPrint('🚀 Opening $walletName via deep link...'); }
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
        } else {
          // Fallback to universal link
          if (kDebugMode) { debugPrint('🌐 Fallback to universal link...'); }
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        }
        
        // Wait for session approval with timeout
        if (kDebugMode) { debugPrint('⏳ Waiting for session approval...'); }
        try {
          final session = await connectResponse.session.future.timeout(
            const Duration(minutes: 2),
            onTimeout: () {
              throw Exception('Connection timeout - user did not approve in MetaMask');
            },
          );
          _session = session;
          _extractAddressFromSession();
          
          // Save session securely
          if (_connectedAddress != null && _chainId != null) {
            await app_session.SessionService.instance.saveSession(
              app_session.SessionData(
                walletAddress: _connectedAddress!,
                walletProvider: walletName,
                chainId: _chainId!,
                connectedAt: DateTime.now(),
                sessionTopic: session.topic,
              ),
            );
          }
          
          if (kDebugMode) { debugPrint('✅ Session approved! Address: $_connectedAddress'); }
          notifyListeners();
          return true;
        } catch (e) {
          if (kDebugMode) { debugPrint('❌ Session approval failed: $e'); }
          rethrow;
        }
      }
      
      return false;
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ WalletConnect error: $e'); }
      rethrow;
    }
  }
  
  /// Disconnect wallet
  Future<void> disconnect() async {
    if (_session != null && _web3App != null) {
      try {
        await _web3App!.disconnectSession(
          topic: _session!.topic,
          reason: const WalletConnectError(code: 0, message: 'User disconnected'),
        );
      } catch (e) {
        if (kDebugMode) { debugPrint('Error disconnecting WalletConnect session: $e'); }
      }
    }
    _session = null;
    _connectedAddress = null;
    _chainId = null;
    await app_session.SessionService.instance.clearSession();
    notifyListeners();
  }
  
  /// Check if current session is still valid
  Future<bool> _isSessionValid() async {
    if (_session == null || _web3App == null) return false;
    
    try {
      final sessions = _web3App!.sessions.getAll();
      return sessions.any((s) => s.topic == _session!.topic);
    } catch (e) {
      if (kDebugMode) { debugPrint('Session validation error: $e'); }
      return false;
    }
  }
  
  /// Ensure we have a valid session, reconnect if needed
  Future<void> ensureConnected() async {
    if (!await _isSessionValid()) {
      if (kDebugMode) { debugPrint('⚠️ Session invalid, clearing and requiring reconnect...'); }
      _session = null;
      _connectedAddress = null;
      _chainId = null;
      await app_session.SessionService.instance.clearSession();
      notifyListeners();
      throw Exception('Session expired. Please reconnect to MetaMask.');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // ⚠️  CENTRALIZED TRANSACTION HANDLER — SINGLE ENTRY POINT
  // ════════════════════════════════════════════════════════════════════════
  //
  //  ALL blockchain transactions MUST go through this method.
  //
  //  🚫 MANUAL GAS CONFIGURATION IS STRICTLY PROHIBITED.
  //     MetaMask handles gas estimation automatically via WalletConnect.
  //     Sending a manual 'gas', 'gasLimit', or 'gasPrice' parameter causes
  //     "gas limit too high" errors and blocks the entire mint/auction flow.
  //
  //  ✅ This method only sends: from, to, data, value (optional).
  //     MetaMask will estimate gas (typically 200k–500k for NFT operations).
  //
  //  📌 If you need to debug gas issues, check MetaMask's gas estimation
  //     in the wallet app — NOT by adding gas params here.
  // ════════════════════════════════════════════════════════════════════════

  /// Centralized transaction sender via WalletConnect.
  ///
  /// Gas estimation is handled **entirely by MetaMask** — this method
  /// intentionally does NOT accept or send any gas-related parameters.
  /// This prevents the recurring "gas limit too high" error (code 5000).
  Future<String> sendTransaction({
    required String to,
    required String data,
    String? value,
  }) async {
    if (_session == null || _connectedAddress == null) {
      throw Exception('Wallet not connected');
    }
    
    // Validate session before sending
    await ensureConnected();
    
    try {
      // ── Build transaction params (NO gas parameter) ──
      final txParams = <String, dynamic>{
        'from': _connectedAddress,
        'to': to,
        if (data.isNotEmpty && data != '0x') 'data': data,
        if (value != null) 'value': value,
      };
      
      // ── SAFETY GUARD: Block any accidental gas parameter ──
      // This catches mistakes if someone adds gas params in the future.
      const forbiddenKeys = ['gas', 'gasLimit', 'gasPrice', 'maxFeePerGas', 'maxPriorityFeePerGas'];
      for (final key in forbiddenKeys) {
        if (txParams.containsKey(key)) {
          debugPrint('🚫 BLOCKED: Transaction contains forbidden gas parameter "$key". '
              'Manual gas configuration is prohibited. Removing it.');
          txParams.remove(key);
        }
      }
      
      // ── Debug: Log full transaction payload ──
      if (kDebugMode) { debugPrint('╔══════════════════════════════════════════════════'); }
      if (kDebugMode) { debugPrint('║ 📤 TRANSACTION PAYLOAD'); }
      if (kDebugMode) { debugPrint('║ from: ${txParams['from']}'); }
      if (kDebugMode) { debugPrint('║ to:   ${txParams['to']}'); }
      if (txParams.containsKey('data')) {
        final dataStr = txParams['data'] as String;
        if (kDebugMode) { debugPrint('║ data: ${dataStr.length > 10 ? '${dataStr.substring(0, 10)}...' : dataStr} (${(dataStr.length - 2) ~/ 2} bytes)'); }
      } else {
        if (kDebugMode) { debugPrint('║ data: none'); }
      }
      if (txParams.containsKey('value')) {
        if (kDebugMode) { debugPrint('║ value: ${txParams['value']}'); }
      }
      if (kDebugMode) { debugPrint('║ gas:  ⛽ MetaMask auto-estimate (no manual override)'); }
      if (kDebugMode) { debugPrint('║ keys: ${txParams.keys.toList()}'); }
      if (kDebugMode) { debugPrint('╚══════════════════════════════════════════════════'); }
      
      // ── Send via WalletConnect ──
      final txFuture = _web3App!.request(
        topic: _session!.topic,
        chainId: 'eip155:${ContractConfig.chainId}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [txParams],
        ),
      );
      
      // Open MetaMask to show the transaction popup for user approval
      // This is CRITICAL — without this, the user won't see the popup!
      await _openMetaMaskForTransaction();
      
      if (kDebugMode) { debugPrint('⏳ Waiting for user approval in MetaMask...'); }
      
      // Wait for user to approve/reject in MetaMask
      final txHash = await txFuture.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw Exception('Transaction request timed out in MetaMask'),
      );
      
      if (kDebugMode) { debugPrint('✅ Transaction approved! Hash: $txHash'); }
      return txHash.toString();
    } catch (e) {
      if (kDebugMode) { debugPrint('❌ Transaction failed: $e'); }
      // If session error, clear session and ask to reconnect
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
  
  /// Open wallet app to show pending transaction popup
  /// Uses the WalletConnect session topic to deep-link directly to the
  /// pending transaction, avoiding a redundant "access" prompt in MetaMask.
  Future<void> _openMetaMaskForTransaction() async {
    try {
      // Use the session topic to tell MetaMask which pending request to show.
      // This prevents MetaMask from showing a generic connect/access screen.
      final topic = _session?.topic;
      
      Uri walletUri;
      if (topic != null) {
        // Deep-link with topic — MetaMask will jump straight to the tx popup
        walletUri = Uri.parse('metamask://wc?topic=$topic');
      } else {
        walletUri = Uri.parse('metamask://');
      }
      
      if (await canLaunchUrl(walletUri)) {
        if (kDebugMode) { debugPrint('🦊 Opening MetaMask for transaction approval...'); }
        await launchUrl(walletUri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to universal link with topic
        final universalUri = topic != null
            ? Uri.parse('https://metamask.app.link/wc?topic=$topic')
            : Uri.parse('https://metamask.app.link/');
        if (kDebugMode) { debugPrint('🌐 Fallback: Opening MetaMask via universal link...'); }
        await launchUrl(universalUri, mode: LaunchMode.externalApplication);
      }
      
      // Small delay to allow MetaMask to open and display the pending tx
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Could not open MetaMask: $e'); }
      // Don't throw - the transaction request was still sent,
      // user can manually switch to MetaMask
    }
  }
  
  /// Get balance via RPC
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
            radix: 16
          );
          return balanceWei / BigInt.from(10).pow(18);
        }
      }
      return 0;
    } catch (e) {
      if (kDebugMode) { debugPrint('Error getting balance: $e'); }
      return 0;
    }
  }
  
  @override
  void dispose() {
    _web3App?.onSessionConnect.unsubscribe(_onSessionConnect);
    _web3App?.onSessionDelete.unsubscribe(_onSessionDelete);
    _web3App?.onSessionExpire.unsubscribe(_onSessionExpire);
    _web3App?.onSessionUpdate.unsubscribe(_onSessionUpdate);
    _web3App?.onSessionEvent.unsubscribe(_onSessionEvent);
    super.dispose();
  }
}
