import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String email;
  final String phone;
  final String? publicKey;
  final DateTime? createdAt;

  const UserModel({
    required this.uid,
    required this.username,
    required this.email,
    required this.phone,
    this.publicKey,
    this.createdAt,
  });

  factory UserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserModel(
      uid: doc.id,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      publicKey: data['publicKey'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory UserModel.fromMap(String uid, Map<String, dynamic> data) {
    return UserModel(
      uid: uid,
      username: data['username'] as String? ?? '',
      email: data['email'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      publicKey: data['publicKey'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'username': username,
        'email': email,
        'phone': phone,
        if (publicKey != null) 'publicKey': publicKey,
      };

  bool get hasPublicKey => publicKey != null && publicKey!.isNotEmpty;
}
