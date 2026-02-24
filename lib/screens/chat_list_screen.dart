import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/chat_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import '../theme/app_colors.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final chatService = ChatService();
    final currentUserId = authService.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.transparent,
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
              _buildHeader(context, authService),
              _buildSearchBar(),
              _buildFilterTabs(),
              Expanded(
                child: _buildChatList(chatService, currentUserId, context),
              ),
            ],
          ),
        ),
      ),
      
    );
  }

  Widget _buildHeader(BuildContext context, AuthService authService) {
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
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextField(
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.4)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
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
          _filterChip('Favorite'),
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

  Widget _buildChatList(ChatService chatService, String currentUserId, BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: chatService.getUsers(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
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
            child: Text('Nessun altro utente per ora', style: TextStyle(color: Colors.white)),
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
              userId: userId,
              unreadCount: index < 3 ? (index + 1) : 0,
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
  required String userId,
  int unreadCount = 0,
}) {
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: InkWell(
      onTap: () {
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
                    'Tocca per chattare',
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
                  '12:00',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                if (unreadCount > 0)
                  Container(
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
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

  

  String _getChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }
}