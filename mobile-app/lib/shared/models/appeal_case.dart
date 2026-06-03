import 'package:cloud_firestore/cloud_firestore.dart';

class AppealCase {
  final String caseId;
  final int tokenId;
  final String reporterWallet;
  final String ownerWallet;
  final String status; // 'open', 'resolved'
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolutionType; // 'unfrozen', 'takedown'

  AppealCase({
    required this.caseId,
    required this.tokenId,
    required this.reporterWallet,
    required this.ownerWallet,
    this.status = 'open',
    required this.createdAt,
    this.resolvedAt,
    this.resolutionType,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'caseId': caseId,
      'tokenId': tokenId,
      'reporterWallet': reporterWallet.toLowerCase().trim(),
      'ownerWallet': ownerWallet.toLowerCase().trim(),
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (resolvedAt != null) 'resolvedAt': resolvedAt!.millisecondsSinceEpoch,
      if (resolutionType != null) 'resolutionType': resolutionType,
    };
  }

  factory AppealCase.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    } else if (data['createdAt'] != null && data['createdAt'].runtimeType.toString() == 'Timestamp') {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    }

    DateTime? parsedResolvedAt;
    if (data['resolvedAt'] is int) {
      parsedResolvedAt = DateTime.fromMillisecondsSinceEpoch(data['resolvedAt'] as int);
    } else if (data['resolvedAt'] != null && data['resolvedAt'].runtimeType.toString() == 'Timestamp') {
      parsedResolvedAt = (data['resolvedAt'] as Timestamp).toDate();
    }

    return AppealCase(
      caseId: id,
      tokenId: data['tokenId'] as int? ?? 0,
      reporterWallet: (data['reporterWallet'] as String? ?? '').toLowerCase().trim(),
      ownerWallet: (data['ownerWallet'] as String? ?? '').toLowerCase().trim(),
      status: data['status'] as String? ?? 'open',
      createdAt: parsedCreatedAt,
      resolvedAt: parsedResolvedAt,
      resolutionType: data['resolutionType'] as String?,
    );
  }
}
