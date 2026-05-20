import 'package:cloud_firestore/cloud_firestore.dart';

enum TransferStatus { pending, received, completed }

class TransferModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String fileName;
  final int fileSize;
  final String encryptedAESKey;
  final String iv;
  final String encryptedFileUrl;
  final TransferStatus status;
  final bool sessionActive;
  final bool senderCleanedUp;
  final DateTime? createdAt;
  final DateTime? receivedAt;

  const TransferModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.fileName,
    required this.fileSize,
    required this.encryptedAESKey,
    required this.iv,
    required this.encryptedFileUrl,
    required this.status,
    this.sessionActive = false,
    this.senderCleanedUp = false,
    this.createdAt,
    this.receivedAt,
  });

  factory TransferModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TransferModel(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      fileName: data['fileName'] as String? ?? 'file',
      fileSize: data['fileSize'] as int? ?? 0,
      encryptedAESKey: data['encryptedAESKey'] as String? ?? '',
      iv: data['iv'] as String? ?? '',
      encryptedFileUrl: data['encryptedFileUrl'] as String? ?? '',
      status: _parseStatus(data['status'] as String?),
      sessionActive: data['sessionActive'] as bool? ?? false,
      senderCleanedUp: data['senderCleanedUp'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
    );
  }

  static TransferStatus _parseStatus(String? s) {
    switch (s) {
      case 'received':
        return TransferStatus.received;
      case 'completed':
        return TransferStatus.completed;
      default:
        return TransferStatus.pending;
    }
  }

  Map<String, dynamic> toCreateMap({required String downloadUrl}) => {
        'senderId': senderId,
        'receiverId': receiverId,
        'fileName': fileName,
        'fileSize': fileSize,
        'encryptedAESKey': encryptedAESKey,
        'iv': iv,
        'encryptedFileUrl': downloadUrl,
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
