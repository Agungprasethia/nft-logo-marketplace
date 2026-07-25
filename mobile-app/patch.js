const fs = require('fs');

let content = fs.readFileSync('lib/features/auction/presentation/auction_payment_page.dart', 'utf-8');

// 1. Add imports
content = content.replace("import 'package:nft_logo_marketplace/features/nft/presentation/home_page.dart';", 
import 'package:nft_logo_marketplace/features/nft/presentation/home_page.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nft_logo_marketplace/core/services/web3_service_mobile.dart';);

// 2. Add StreamSubscription
const oldVars =   bool _isProcessingPayment = false;
  bool _isLocallyLocked = false;
  DateTime? _paymentStartedAt;
  String? _pendingTransactionHash;;
const newVars =   bool _isProcessingPayment = false;
  bool _isLocallyLocked = false;
  DateTime? _paymentStartedAt;
  String? _pendingTransactionHash;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;;
content = content.replace(oldVars, newVars);

// 3. Add listener to initState
const oldInit =   @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for orphaned payment on every page open
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForOrphanedPayment());
  };
const newInit =   @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for orphaned payment on every page open
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForOrphanedPayment());

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none) && _pendingTransactionHash != null) {
        if (kDebugMode) { debugPrint('[NETWORK RESTORED] Triggering _checkPaymentRecovery'); }
        _checkPaymentRecovery();
      }
    });
  };
content = content.replace(oldInit, newInit);

// 4. Add dispose
const oldDispose =   @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  };
const newDispose =   @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  };
content = content.replace(oldDispose, newDispose);

// 5. Update _checkPaymentRecovery
const oldCheck =   Future<void> _checkPaymentRecovery() async {
    if (!_isProcessingPayment) return;
    
    if (kDebugMode) { debugPrint('[PAYMENT RECOVERY] Checking on resume. Pending Hash: '); }

    if (_pendingTransactionHash != null) {
      if (kDebugMode) { debugPrint('[PAYMENT RESUME] Hash exists, checking chain status...'); }
      // CASE A: Check blockchain status
      try {
        final status = await _web3.getTransactionStatus(_pendingTransactionHash!);
        if (status == true) {
          if (kDebugMode) { debugPrint('[PAYMENT RESUME] Transaction SUCCESS on chain. Triggering recovery.'); }
          // Transaction is confirmed on-chain — attempt to complete the Firestore transfer
          // in case the earlier completePayment() call failed due to the status bug.
          final wallet = _web3.currentAddress;
          if (wallet != null && mounted) {
            final recovered = await FirestoreService.instance.recoverOrphanedPayment(
              widget.tokenId, wallet, _pendingTransactionHash!,
            );
            if (recovered && mounted) {
              Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog
              await _handleSuccessfulPayment(_pendingTransactionHash!);
            }
          }
        } else {
          if (kDebugMode) { debugPrint('[PAYMENT RESET] Transaction FAILED or NOT FOUND on chain.'); }
          
          await FirestoreService.instance.setPaymentProcessing(widget.tokenId, false);
          
          if (mounted) {
            setState(() {
              _isProcessingPayment = false;
              _paymentStartedAt = null;
              _pendingTransactionHash = null;
            });
            
            Navigator.of(context, rootNavigator: true).pop();
            
            NotificationManager.show(
              context: context,
              title: 'Payment Failed',
              message: 'Blockchain transaction failed or not found.',
              type: NotificationType.error,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) { debugPrint('[PAYMENT RESET] Error checking tx status: '); }
      }
    } else {;

const newCheck =   Future<void> _checkPaymentRecovery() async {
    if (!_isProcessingPayment) return;
    
    if (kDebugMode) { debugPrint('[PAYMENT RECOVERY] Checking on resume. Pending Hash: '); }

    if (_pendingTransactionHash != null) {
      if (kDebugMode) { debugPrint('[PAYMENT RESUME] Hash exists, checking chain status...'); }
      // CASE A: Check blockchain status
      try {
        final status = await (_web3 as Web3ServiceMobile).getTransactionStatusDetailed(_pendingTransactionHash!);
        
        if (status == TransactionStatusDetailed.success) {
          if (kDebugMode) { debugPrint('[PAYMENT RESUME] Transaction SUCCESS on chain. Triggering recovery.'); }
          final wallet = _web3.currentAddress;
          if (wallet != null && mounted) {
            final recovered = await FirestoreService.instance.recoverOrphanedPayment(
              widget.tokenId, wallet, _pendingTransactionHash!,
            );
            if (recovered && mounted) {
              Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog
              await _handleSuccessfulPayment(_pendingTransactionHash!);
            }
          }
        } else if (status == TransactionStatusDetailed.reverted) {
          if (kDebugMode) { debugPrint('[PAYMENT RESET] Transaction REVERTED on chain.'); }
          await FirestoreService.instance.setPaymentProcessing(widget.tokenId, false);
          
          if (mounted) {
            setState(() {
              _isProcessingPayment = false;
              _paymentStartedAt = null;
              _pendingTransactionHash = null;
            });
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(_txHashStorageKey);
            } catch (_) {}
            
            Navigator.of(context, rootNavigator: true).pop();
            NotificationManager.show(
              context: context,
              title: 'Payment Failed',
              message: 'Transaction reverted on blockchain. You can safely try paying again.',
              type: NotificationType.error,
            );
          }
        } else if (status == TransactionStatusDetailed.pending) {
          if (kDebugMode) { debugPrint('[PAYMENT PENDING] Transaction still pending.'); }
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog, keep state
            NotificationManager.show(
              context: context,
              title: 'Transaction Pending',
              message: 'Transaction is still pending on the blockchain. Please wait.',
              type: NotificationType.warning,
            );
          }
        } else if (status == TransactionStatusDetailed.networkError) {
          if (kDebugMode) { debugPrint('[PAYMENT PENDING] Network error while checking.'); }
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog, keep state
            NotificationManager.show(
              context: context,
              title: 'Cannot Check Status',
              message: 'Cannot check transaction status. Please check your internet connection.',
              type: NotificationType.warning,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) { debugPrint('[PAYMENT RESET] Error checking tx status: '); }
      }
    } else {;
content = content.replace(oldCheck, newCheck);

// Guard in _processPayment
const oldProcess =   Future<void> _processPayment(LogoNFT logo, Auction auction) async {
    if (_isLocallyLocked) {;
const newProcess =   Future<void> _processPayment(LogoNFT logo, Auction auction) async {
    if (_isLocallyLocked) {
      if (kDebugMode) { debugPrint('[PaymentFlow] Blocked by local mutex - already processing'); }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final existingTxHash = prefs.getString(_txHashStorageKey);
      if (existingTxHash != null && existingTxHash.isNotEmpty) {
        if (kDebugMode) { debugPrint('[PaymentFlow] Guard active: Pending transaction found.'); }
        NotificationManager.show(
          context: context,
          title: 'Transaction Pending',
          message: 'You have a pending transaction. We are checking its status.',
          type: NotificationType.warning,
        );
        setState(() {
          _isProcessingPayment = true;
          _pendingTransactionHash = existingTxHash;
        });
        await _checkPaymentRecovery();
        return;
      }
    } catch (_) {}

    if (_isLocallyLocked) {;
content = content.replace(oldProcess, newProcess);

// Callback onTxHashReady in _processPayment
const oldPayWinner =       final txHash = await _web3.payAuctionWinner(logo.creatorWallet, auction.highestBid);
      if (mounted) {
        setState(() => _pendingTransactionHash = txHash);
      }
      
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_txHashStorageKey, txHash);
      } catch (_) {};
const newPayWinner =       final txHash = await (_web3 as Web3ServiceMobile).payAuctionWinner(
        logo.creatorWallet, 
        auction.highestBid,
        onTxHashReady: (hash) async {
          if (mounted) {
            setState(() => _pendingTransactionHash = hash);
          }
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_txHashStorageKey, hash);
          } catch (_) {}
        },
      );;
content = content.replace(oldPayWinner, newPayWinner);

// Catch Network Loss
const oldCatch =     } catch (e) {
      if (!mounted) return;
      if (kDebugMode) { debugPrint('[PaymentFlow] Payment Failed or Rejected: '); }
      Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog
      
      final errorText = e.toString().toLowerCase();
      final isRejected = errorText.contains('reject') || errorText.contains('denied');
      NotificationManager.show(
        context: context,
        title: 'Payment Failed',
        message: isRejected ? 'User rejected the transaction' : e.toString().replaceAll('Exception: ', ''),
        type: NotificationType.error,
      );
    } finally {;
const newCatch =     } catch (e) {
      if (!mounted) return;
      if (kDebugMode) { debugPrint('[PaymentFlow] Payment Failed or Rejected: '); }
      
      final errorText = e.toString().toLowerCase();
      
      if (errorText.contains('network_loss')) {
        Navigator.of(context, rootNavigator: true).pop(); // Close dialog
        NotificationManager.show(
          context: context,
          title: 'Cannot Check Status',
          message: 'Cannot check transaction status. Please check your internet connection.',
          type: NotificationType.warning,
        );
        // Do NOT clear _isProcessingPayment or _pendingTransactionHash so UI stays locked
        _isLocallyLocked = false;
        return;
      }
      
      Navigator.of(context, rootNavigator: true).pop(); // Close processing dialog
      
      final isRejected = errorText.contains('reject') || errorText.contains('denied');
      NotificationManager.show(
        context: context,
        title: 'Payment Failed',
        message: isRejected ? 'User rejected the transaction' : e.toString().replaceAll('Exception: ', ''),
        type: NotificationType.error,
      );
    } finally {;
content = content.replace(oldCatch, newCatch);

fs.writeFileSync('lib/features/auction/presentation/auction_payment_page.dart', content, 'utf-8');