import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionData {
  final String walletAddress;
  final String walletProvider;
  final int chainId;
  final DateTime connectedAt;
  final DateTime lastConnectedAt;
  final String sessionType; // 'marketplace' or 'admin'
  final String sessionSchemaVersion;
  final String? sessionTopic; // Used for WalletConnect

  SessionData({
    required this.walletAddress,
    required this.walletProvider,
    required this.chainId,
    required this.connectedAt,
    DateTime? lastConnectedAt,
    this.sessionType = 'marketplace',
    this.sessionSchemaVersion = '1.0.0',
    this.sessionTopic,
  }) : lastConnectedAt = lastConnectedAt ?? connectedAt;

  Map<String, dynamic> toJson() {
    return {
      'walletAddress': walletAddress,
      'walletProvider': walletProvider,
      'chainId': chainId,
      'connectedAt': connectedAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt.toIso8601String(),
      'sessionType': sessionType,
      'sessionSchemaVersion': sessionSchemaVersion,
      if (sessionTopic != null) 'sessionTopic': sessionTopic,
    };
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      walletAddress: json['walletAddress'] as String? ?? '',
      walletProvider: json['walletProvider'] as String? ?? 'metamask',
      chainId: json['chainId'] as int? ?? 11155111,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'])
          : DateTime.now(),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'])
          : null,
      sessionType: json['sessionType'] as String? ?? 'marketplace',
      sessionSchemaVersion: json['sessionSchemaVersion'] as String? ?? '1.0.0',
      sessionTopic: json['sessionTopic'] as String?,
    );
  }

  SessionData copyWith({
    String? walletAddress,
    String? walletProvider,
    int? chainId,
    DateTime? connectedAt,
    DateTime? lastConnectedAt,
    String? sessionType,
    String? sessionSchemaVersion,
    String? sessionTopic,
  }) {
    return SessionData(
      walletAddress: walletAddress ?? this.walletAddress,
      walletProvider: walletProvider ?? this.walletProvider,
      chainId: chainId ?? this.chainId,
      connectedAt: connectedAt ?? this.connectedAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      sessionType: sessionType ?? this.sessionType,
      sessionSchemaVersion: sessionSchemaVersion ?? this.sessionSchemaVersion,
      sessionTopic: sessionTopic ?? this.sessionTopic,
    );
  }
}

class SessionService {
  static final SessionService instance = SessionService._internal();
  SessionService._internal();

  static const String _marketplaceSessionKey = 'leo_marketplace_session';
  static const String _adminSessionKey = 'leo_admin_session';
  static const Duration _maxSessionAge = Duration(hours: 24);
  
  String _getKeyForType(String sessionType) {
    return sessionType == 'admin' ? _adminSessionKey : _marketplaceSessionKey;
  }

  Future<void> saveSession(SessionData session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(session.toJson());
      await prefs.setString(_getKeyForType(session.sessionType), jsonString);
      await saveLastConnectedWallet(session.walletAddress);
      if (kDebugMode) { debugPrint('✅ Wallet session saved to SharedPreferences (${session.sessionType})'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error saving wallet session: $e'); }
    }
  }

  Future<SessionData?> getSession({String sessionType = 'marketplace'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_getKeyForType(sessionType));
      if (jsonString != null) {
        final json = jsonDecode(jsonString);
        return SessionData.fromJson(json);
      }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error reading wallet session: $e'); }
      await clearSession(sessionType: sessionType);
    }
    return null;
  }

  Future<bool> hasValidSession({String sessionType = 'marketplace'}) async {
    final session = await getSession(sessionType: sessionType);
    if (session == null) return false;

    // Check expiration (7 days)
    if (isSessionStale(session)) {
      if (kDebugMode) { debugPrint('⏰ Session is stale (older than ${_maxSessionAge.inDays} days).'); }
      return false; // Don't clear immediately here, let the UI handle it gracefully
    }

    // Strict validation
    if (session.walletAddress.isEmpty) {
      return false;
    }

    // Schema version check
    if (session.sessionSchemaVersion != '1.0.0') {
      if (kDebugMode) { debugPrint('⚠️ Session schema mismatch. Expected 1.0.0, got ${session.sessionSchemaVersion}'); }
      return false;
    }

    return true;
  }
  
  /// Fingerprint validation: Called when reconnecting to verify the wallet hasn't changed.
  bool validateFingerprint(SessionData session, String currentAddress, int currentChainId, String currentProvider) {
    if (session.walletAddress.toLowerCase() != currentAddress.toLowerCase()) {
      if (kDebugMode) { debugPrint('⚠️ Fingerprint mismatch: Wallet address changed'); }
      return false;
    }
    if (session.chainId != currentChainId) {
      if (kDebugMode) { debugPrint('⚠️ Fingerprint mismatch: Chain ID changed'); }
      return false;
    }
    if (session.walletProvider != currentProvider) {
      if (kDebugMode) { debugPrint('⚠️ Fingerprint mismatch: Provider changed'); }
      return false;
    }
    return true;
  }

  bool isSessionStale(SessionData session) {
    final age = DateTime.now().difference(session.lastConnectedAt);
    return age > _maxSessionAge;
  }

  Future<void> updateLastConnected({String sessionType = 'marketplace'}) async {
    final session = await getSession(sessionType: sessionType);
    if (session != null) {
      final updated = session.copyWith(lastConnectedAt: DateTime.now());
      await saveSession(updated);
      if (kDebugMode) { debugPrint('🔄 Session lastConnectedAt refreshed ($sessionType)'); }
    }
  }

  Future<void> clearSession({String sessionType = 'marketplace'}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getKeyForType(sessionType));
      if (kDebugMode) { debugPrint('🔌 Wallet session cleared from SharedPreferences ($sessionType)'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error clearing wallet session: $e'); }
    }
  }

  /// Extremely comprehensive logout - clears EVERYTHING
  Future<void> fullLogout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_marketplaceSessionKey);
      await prefs.remove(_adminSessionKey);
      // We intentionally do NOT clear 'leo_last_connected_wallet' to show it as a hint on WalletGatePage
      if (kDebugMode) { debugPrint('🚨 FULL LOGOUT: All SharedPreferences cleared.'); }
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error during full logout: $e'); }
    }
  }

  /// Optional: Save last connected wallet for "Last Connected" UX
  Future<void> saveLastConnectedWallet(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('leo_last_connected_wallet', address);
    } catch (e) {
      if (kDebugMode) { debugPrint('⚠️ Error saving last connected wallet: $e'); }
    }
  }

  Future<String?> getLastConnectedWallet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('leo_last_connected_wallet');
    } catch (e) {
      return null;
    }
  }
}
