import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ChatScreen extends StatefulWidget {
  final String contactName;
  final Color contactColor;
  final String chatId;

  const ChatScreen({
    super.key,
    required this.contactName,
    required this.contactColor,
    required this.chatId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ChatService _chatService = ChatService();
  final ItemScrollController _itemScrollController = ItemScrollController();
  int _lastKnownMessageCount = 0;
  bool _isUploadingImage = false;
  final String _myId = AuthService().currentUser?.uid ?? 'anonimo';
  StreamSubscription<int>? _unreadSub;
  late final Stream<QuerySnapshot> _messagesStream;

  @override
  void initState() {
    super.initState();
    _messagesStream = _chatService.getMessages(widget.chatId);
    _chatService.markAsRead(widget.chatId, _myId);
    _unreadSub = _chatService
        .getUnreadCount(widget.chatId, _myId)
        .listen((count) {
      if (count > 0) {
        _chatService.markAsRead(widget.chatId, _myId);
      }
    });
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _chatService.sendMessage(widget.chatId, text, _myId);
    _controller.clear();
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    try {
      setState(() => _isUploadingImage = true);
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      await _chatService.sendImage(widget.chatId, _myId, bytes);
    } catch (e) {
      debugPrint('Errore invio immagine: $e');
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }

  String _formatTime24Hour(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background/bgdark.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Nessun messaggio',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }

                  final messages = snapshot.data!.docs;

                  if (messages.length > _lastKnownMessageCount) {
                    final isNewMessage = _lastKnownMessageCount > 0;
                    _lastKnownMessageCount = messages.length;
                    if (isNewMessage) {
                      final newDummyIndex = messages.length;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_itemScrollController.isAttached) {
                          _itemScrollController.jumpTo(
                            index: newDummyIndex,
                            alignment: 1.0,
                          );
                        }
                      });
                    }
                  }

                  return ScrollablePositionedList.builder(
                    itemCount: messages.length + 1,
                    initialScrollIndex: messages.length,
                    initialAlignment: 1.0,
                    itemScrollController: _itemScrollController,
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                    ),
                    itemBuilder: (context, index) {
                      if (index == messages.length) return const SizedBox.shrink();
                      final data =
                          messages[index].data() as Map<String, dynamic>;
                      final isMe = data['senderId'] == _myId;
                      final type = data['type'] as String? ?? 'text';
                      final timestamp = data['timestamp'] as Timestamp?;
                      final time = timestamp != null
                          ? _formatTime24Hour(timestamp.toDate())
                          : '';

                      const showTimestamp = true;

                      Widget? dateSeparator;
                      if (timestamp != null) {
                        final messageDate = timestamp.toDate();
                        bool showSeparator = false;
                        if (index == 0) {
                          showSeparator = true;
                        } else {
                          final prevData =
                              messages[index - 1].data() as Map<String, dynamic>;
                          final prevTimestamp =
                              prevData['timestamp'] as Timestamp?;
                          if (prevTimestamp != null) {
                            final prevDate = prevTimestamp.toDate();
                            if (DateTime(messageDate.year, messageDate.month,
                                    messageDate.day) !=
                                DateTime(prevDate.year, prevDate.month,
                                    prevDate.day)) {
                              showSeparator = true;
                            }
                          }
                        }
                        if (showSeparator) {
                          dateSeparator = _buildDateSeparator(messageDate);
                        }
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (dateSeparator != null) dateSeparator,
                          _buildMessageBubble(
                            context: context,
                            data: data,
                            isMe: isMe,
                            type: type,
                            time: time,
                            showTimestamp: showTimestamp,
                          ),
                          if (index == messages.length - 1)
                            const SizedBox(height: 8),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_isUploadingImage)
              LinearProgressIndicator(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                color: AppColors.primary,
              ),
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: _buildInputBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              backgroundColor: AppColors.primary,
              radius: 20,
              child: Text(
                widget.contactName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'online',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    }
  }

  Widget _buildDateSeparator(DateTime date) {
    final label = _formatDateLabel(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.15),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required BuildContext context,
    required Map<String, dynamic> data,
    required bool isMe,
    required String type,
    required String time,
    required bool showTimestamp,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: type == 'image'
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: type == 'image'
                  ? Colors.transparent
                  : isMe
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
            ),
            child: type == 'image'
                ? Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenImage(
                                imageUrl: data['imageUrl'] as String,
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            data['imageUrl'] as String,
                            width: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (showTimestamp && time.isNotEmpty)
                        Positioned(
                          bottom: 6,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 3),
                                  const Icon(Icons.done_all,
                                      size: 12, color: Colors.white),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data['text'] as String,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      if (showTimestamp && time.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 3),
                              Icon(
                                Icons.done_all,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 12, 12, 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.attach_file,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            onPressed: _sendImage,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Type here...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.send, color: Colors.white.withValues(alpha: 0.6)),
            onPressed: () {
              (_) => _sendMessage();
            },
          ),
        ],
      ),
    );
  }
}

class FullScreenImage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: InteractiveViewer(
        panEnabled: true,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 1.0,
        maxScale: 4.0,
        child: Center(child: Image.network(imageUrl)),
      ),
    );
  }
}
