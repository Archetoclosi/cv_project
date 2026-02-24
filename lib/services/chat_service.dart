import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'cloudinary_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> sendMessage(String chatId, String text, String senderId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'text': text,
      'senderId': senderId,
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendImage(String chatId, String senderId, Uint8List imageBytes) async {
  final cloudinary = CloudinaryService();
  final url = await cloudinary.uploadImage(imageBytes);
  
  if (url == null) return;

  await _db
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .add({
    'imageUrl': url,
    'senderId': senderId,
    'type': 'image',
    'timestamp': FieldValue.serverTimestamp(),
  });
}

  Stream<QuerySnapshot> getMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  Stream<QuerySnapshot> getUsers(String currentUserId) {
    return _db.collection('users').snapshots();
  }
}