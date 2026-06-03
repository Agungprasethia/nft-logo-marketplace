import 'package:cloud_firestore/cloud_firestore.dart';

class AppealMessage {
  final String messageId;
  final String caseId;
  final String senderWallet;
  final String senderRole; // 'reporter', 'owner', 'admin'
  final String message;
  final List<String>? evidenceUrls;
  final DateTime timestamp;

  AppealMessage({
    required this.messageId,
    required this.caseId,
    required this.senderWallet,
    required this.senderRole,
    required this.message,
    this.evidenceUrls,
    required this.timestamp,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'messageId': messageId,
      'caseId': caseId,
      'senderWallet': senderWallet.toLowerCase().trim(),
      'senderRole': senderRole,
      'message': message,
      if (evidenceUrls != null) 'evidenceUrls': evidenceUrls,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory AppealMessage.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime parsedTimestamp = DateTime.now();
    if (data['timestamp'] is int) {
      parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
    } else if (data['timestamp'] != null && data['timestamp'].runtimeType.toString() == 'Timestamp') {
      parsedTimestamp = (data['timestamp'] as Timestamp).toDate();
    }

    return AppealMessage(
      messageId: id,
      caseId: data['caseId'] as String? ?? '',
      senderWallet: (data['senderWallet'] as String? ?? '').toLowerCase().trim(),
      senderRole: data['senderRole'] as String? ?? 'user',
      message: data['message'] as String? ?? '',
      evidenceUrls: (data['evidenceUrls'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      timestamp: parsedTimestamp,
    );
  }
}
