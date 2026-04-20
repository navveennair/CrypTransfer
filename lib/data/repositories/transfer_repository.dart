import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/transfer_model.dart';
import '../models/notification_model.dart';

class TransferRepository {
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  TransferRepository({
    FirebaseFirestore? db,
    FirebaseStorage? storage,
  })  : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  // ─── Generate a new transfer ID ────────────────────────────────────────────

  String generateId() =>
      _db.collection(FirebaseConstants.transfers).doc().id;

  // ─── Upload encrypted file and create transfer document ───────────────────

  /// Uploads [encryptedBytes] to Storage then writes the transfer document.
  /// Returns a stream of upload progress (0.0 → 1.0) and completes when done.
  Stream<double> uploadAndCreate({
    required String transferId,
    required Uint8List encryptedBytes,
    required String fileName,
    required int fileSize,
    required String senderId,
    required String receiverId,
    required String encryptedAESKeyB64,
    required String ivB64,
  }) async* {
    try {
      final ref = _storage.ref(
          '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}');

      final metadata = SettableMetadata(
        contentType: 'application/octet-stream',
        customMetadata: {'fileName': fileName},
      );

      final task = ref.putData(encryptedBytes, metadata);

      await for (final snapshot in task.snapshotEvents) {
        if (snapshot.totalBytes > 0) {
          yield snapshot.bytesTransferred / snapshot.totalBytes;
        }
      }

      final snapshot = await task;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': senderId,
        'receiverId': receiverId,
        'encryptedAESKey': encryptedAESKeyB64,
        'encryptedFileUrl': downloadUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'iv': ivB64,
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      yield 1.0;
    } on FirebaseException catch (e) {
      throw TransferException(
          'Upload failed: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Notify receiver ───────────────────────────────────────────────────────

  Future<void> notifyReceiver({
    required String receiverId,
    required String senderUsername,
    required String transferId,
  }) async {
    try {
      final notif = NotificationModel(
        id: '',
        toUserId: receiverId,
        fromUsername: senderUsername,
        message: '📁 $senderUsername sent you an encrypted file',
        type: NotificationType.fileReceived,
        transferId: transferId,
        read: false,
      );
      await _db
          .collection(FirebaseConstants.users)
          .doc(receiverId)
          .collection(FirebaseConstants.notifications)
          .add(notif.toCreateMap());
    } catch (_) {
      // Non-critical — notification failure must not break the transfer
    }
  }

  // ─── Fetch transfer document ───────────────────────────────────────────────

  Future<TransferModel> getTransfer(String transferId) async {
    try {
      final doc = await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .get();
      if (!doc.exists) {
        throw TransferException('Transfer not found', code: 'not-found');
      }
      return TransferModel.fromDoc(doc);
    } on TransferException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransferException(
          'Failed to load transfer: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Mark transfer as received ─────────────────────────────────────────────

  Future<void> markReceived(String transferId) async {
    try {
      await _db
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .update({
        'status': 'received',
        'receivedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw TransferException(
          'Failed to update transfer status: ${e.message ?? e.code}',
          code: e.code);
    }
  }

  // ─── Download encrypted file ───────────────────────────────────────────────

  Future<Uint8List> downloadEncryptedFile(String transferId) async {
    try {
      final ref = _storage.ref(
          '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}');
      final bytes = await ref.getData(FirebaseConstants.maxDownloadBytes);
      if (bytes == null) {
        throw TransferException('File download returned no data');
      }
      return bytes;
    } on TransferException {
      rethrow;
    } on FirebaseException catch (e) {
      throw TransferException(
          'File download failed: ${e.message ?? e.code}', code: e.code);
    }
  }

  // ─── Delete encrypted file from Storage ───────────────────────────────────

  Future<void> deleteStorageFile(String transferId) async {
    try {
      await _storage
          .ref(
              '${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}')
          .delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  // ─── Write audit log ───────────────────────────────────────────────────────

  Future<void> writeAuditLog({
    required String senderId,
    required String receiverId,
    required String fileName,
    required int fileSize,
    required String status,
  }) async {
    await _db
        .collection(FirebaseConstants.transferLogs)
        .add({
      'senderId': senderId,
      'receiverId': receiverId,
      'participants': [senderId, receiverId],
      'fileName': fileName,
      'fileSize': fileSize,
      'status': status,
      'loggedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Delete transfer document ──────────────────────────────────────────────

  Future<void> deleteTransfer(String transferId) async {
    await _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .delete();
  }

  // ─── Update receiver status ────────────────────────────────────────────────

  Future<void> updateReceiverStatus(
    String transferId,
    String status,
  ) async {
    await _db
        .collection(FirebaseConstants.transfers)
        .doc(transferId)
        .update({
      'receiverStatus': status,
      'receiverStatusUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Real-time listener for pending transfers ──────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingTransfers(
      String receiverId) {
    return _db
        .collection(FirebaseConstants.transfers)
        .where('receiverId', isEqualTo: receiverId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }
}

