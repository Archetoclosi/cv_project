import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/whats_new_sheet.dart';

String _formatChatDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDate = DateTime(date.year, date.month, date.day);
  final differenceInDays = today.difference(messageDate).inDays;

  if (messageDate == today) {
    // Same day — show HH:mm
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  } else if (differenceInDays < 7) {
    // Within the last 7 days — show abbreviated weekday
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  } else {
    // Older — show dd/MM
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WhatsNewSheet.showIfNew(context);
    });
  }

  String _getChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _authService.currentUser!.uid;

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
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              const _SearchBar(),
              _buildFilterTabs(),
              Expanded(
                child: _buildChatList(currentUserId, context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Chats',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.new_releases_outlined, color: Colors.white),
                tooltip: "What's New",
                onPressed: () => WhatsNewSheet.showManually(context),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () async {
                  await _authService.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _filterChip('All', selected: true),
          const SizedBox(width: 8),
          _filterChip('Unread'),
          const SizedBox(width: 8),
          _filterChip('Favorites'),
        ],
      ),
    );
  }

  Widget _filterChip(String label, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildChatList(String currentUserId, BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getUsers(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('Nessun utente', style: TextStyle(color: Colors.white)),
          );
        }

        final users = snapshot.data!.docs
            .where((doc) => doc.id != currentUserId)
            .toList();

        if (users.isEmpty) {
          return const Center(
            child: Text(
              'Nessun altro utente per ora',
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final nickname = data['nickname'] as String;
            final userId = users[index].id;
            final chatId = _getChatId(currentUserId, userId);

            return _buildChatTile(
              context: context,
              nickname: nickname,
              chatId: chatId,
              currentUserId: currentUserId,
            );
          },
        );
      },
    );
  }

  Widget _buildChatTile({
    required BuildContext context,
    required String nickname,
    required String chatId,
    required String currentUserId,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getLastMessageStream(chatId),
      builder: (context, msgSnapshot) {
        String displayTime = '--:--';
        String lastMessagePreview = '';
        if (msgSnapshot.hasData && msgSnapshot.data!.docs.isNotEmpty) {
          final msgData =
              msgSnapshot.data!.docs.first.data() as Map<String, dynamic>;
          final rawTimestamp = msgData['timestamp'];
          if (rawTimestamp is Timestamp) {
            displayTime = _formatChatDate(rawTimestamp.toDate());
          }
          final msgType = msgData['type'] as String?;
          if (msgType == 'image') {
            lastMessagePreview = '📷 Photo';
          } else {
            lastMessagePreview = msgData['text'] as String? ?? '';
          }
        }

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: () {
              FocusScope.of(context).unfocus();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    contactName: nickname,
                    contactColor: AppColors.primary,
                    chatId: chatId,
                  ),
                ),
              );
            },
            splashColor: Colors.white.withValues(alpha: 0.05),
            highlightColor: Colors.white.withValues(alpha: 0.05),
            hoverColor: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      nickname[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nickname,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastMessagePreview.isEmpty
                              ? 'No messages yet'
                              : lastMessagePreview,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        displayTime,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<int>(
                        stream: _chatService.getUnreadCount(
                            chatId, currentUserId),
                        builder: (context, unreadSnapshot) {
                          final unreadCount = unreadSnapshot.data ?? 0;
                          if (unreadCount <= 0) return const SizedBox.shrink();
                          return Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          focusNode: _focusNode,
          autofocus: false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}
