import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationType { rsaKeyReceived, fileReceived, unknown }

class NotificationModel {
  final String id;
  final String toUserId;
  final String fromUsername;
  final String message;
  final NotificationType type;
  final String? transferId;
  final bool read;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.toUserId,
    required this.fromUsername,
    required this.message,
    required this.type,
    this.transferId,
    required this.read,
    this.createdAt,
  });

  factory NotificationModel.fromMap(String id, Map<String, dynamic> data) {
    return NotificationModel(
      id: id,
      toUserId: data['toUserId'] as String? ?? '',
      fromUsername: data['fromUsername'] as String? ?? '',
      message: data['message'] as String? ?? '',
      type: _parseType(data['type'] as String?),
      transferId: data['transferId'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  static NotificationType _parseType(String? t) {
    switch (t) {
      case 'rsa_key_received':
        return NotificationType.rsaKeyReceived;
      case 'file_received':
        return NotificationType.fileReceived;
      default:
        return NotificationType.unknown;
    }
  }

  static String typeToString(NotificationType t) {
    switch (t) {
      case NotificationType.rsaKeyReceived:
        return 'rsa_key_received';
      case NotificationType.fileReceived:
        return 'file_received';
      case NotificationType.unknown:
        return 'unknown';
    }
  }

  Map<String, dynamic> toCreateMap() => {
        'toUserId': toUserId,
        'fromUsername': fromUsername,
        'message': message,
        'type': typeToString(type),
        if (transferId != null) 'transferId': transferId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
