import 'package:flutter/foundation.dart';

/// In-memory report storage service.
/// Stores artwork reports and prevents duplicate reports
/// from the same wallet for the same token within a cooldown period.
class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  /// Cooldown duration before the same wallet can report the same NFT again.
  static const Duration reportCooldown = Duration(hours: 24);

  /// All stored reports.
  final List<ArtworkReport> _reports = [];

  List<ArtworkReport> get reports => List.unmodifiable(_reports);

  /// Check if a wallet has recently reported a specific token.
  bool hasRecentReport(int tokenId, String walletAddress) {
    final now = DateTime.now();
    return _reports.any((r) =>
        r.tokenId == tokenId &&
        r.reporterAddress.toLowerCase() == walletAddress.toLowerCase() &&
        now.difference(r.timestamp) < reportCooldown);
  }

  /// Submit a new report. Returns the created report.
  /// Throws if the wallet has already reported this token recently.
  ArtworkReport submitReport({
    required int tokenId,
    required String reporterAddress,
    required String reason,
  }) {
    if (hasRecentReport(tokenId, reporterAddress)) {
      throw Exception(
          'You have already reported this artwork. Please wait before reporting again.');
    }

    final report = ArtworkReport(
      id: _reports.length + 1,
      tokenId: tokenId,
      reporterAddress: reporterAddress,
      reason: reason,
      timestamp: DateTime.now(),
    );

    _reports.add(report);
    if (kDebugMode) { debugPrint('📋 Report #${report.id} submitted for token $tokenId'); }
    return report;
  }

  /// Remove all reports for a specific token.
  void removeReport(int tokenId) {
    _reports.removeWhere((r) => r.tokenId == tokenId);
    if (kDebugMode) { debugPrint('🗑️ Reports removed for token $tokenId'); }
  }

  /// Get all reports for a specific token.
  List<ArtworkReport> getReportsForToken(int tokenId) {
    return _reports.where((r) => r.tokenId == tokenId).toList();
  }
}

/// Data model for an artwork report.
class ArtworkReport {
  final int id;
  final int tokenId;
  final String reporterAddress;
  final String reason;
  final DateTime timestamp;

  ArtworkReport({
    required this.id,
    required this.tokenId,
    required this.reporterAddress,
    required this.reason,
    required this.timestamp,
  });
}
