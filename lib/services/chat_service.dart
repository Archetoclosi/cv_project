import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'cloudinary_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> sendMessage(String chatId, String text, String senderId) async {
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'text': text,
      'senderId': senderId,
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendImage(
    String chatId,
    String senderId,
    Uint8List imageBytes,
  ) async {
    final cloudinary = CloudinaryService();
    final url = await cloudinary.uploadImage(imageBytes);

    if (url == null) return;

    await _db.collection('chats').doc(chatId).collection('messages').add({
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

  Future<Map<String, dynamic>?> getLastMessage(String chatId) async {
    final messages = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (messages.docs.isEmpty) return null;
    return messages.docs.first.data();
  }

  Stream<QuerySnapshot> getLastMessageStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots();
  }

  Stream<int> getUnreadCount(String chatId, String userId) {
    return _db.collection('chats').doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return 0;
      final data = doc.data();
      if (data == null) return 0;
      final unreadCounts = data['unreadCounts'] as Map<String, dynamic>?;
      if (unreadCounts == null) return 0;
      return (unreadCounts[userId] as num?)?.toInt() ?? 0;
    });
  }

  Stream<int> getTotalUnreadCount(String userId, List<String> chatIds) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      int total = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final unreadCounts = data['unreadCounts'] as Map<String, dynamic>?;
        if (unreadCounts == null) continue;
        total += (unreadCounts[userId] as num?)?.toInt() ?? 0;
      }
      return total;
    });
  }

  Future<void> markAsRead(String chatId, String userId) async {
    await _db.collection('chats').doc(chatId).set(
      {'unreadCounts': {userId: 0}},
      SetOptions(merge: true),
    );
  }
}
