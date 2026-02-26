import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

export const onNewMessage = functions.firestore
  .document('chats/{chatId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const { chatId } = context.params;
    const message = snap.data();
    const senderId: string = message.senderId;

    // Derive participants from chatId (format: uid1_uid2, sorted)
    const participants = chatId.split('_');
    const recipientId = participants.find((id: string) => id !== senderId);
    if (!recipientId) return;

    // Update unreadCounts and chat metadata atomically
    const chatRef = db.collection('chats').doc(chatId);
    await chatRef.set(
      {
        participants,
        unreadCounts: {
          [recipientId]: admin.firestore.FieldValue.increment(1),
        },
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // Query total unread for recipient across all chats
    const chatsSnapshot = await db
      .collection('chats')
      .where('participants', 'array-contains', recipientId)
      .get();

    let totalUnread = 0;
    for (const chatDoc of chatsSnapshot.docs) {
      const data = chatDoc.data();
      const unreadCounts = data.unreadCounts as
        | Record<string, number>
        | undefined;
      if (unreadCounts) {
        totalUnread += unreadCounts[recipientId] ?? 0;
      }
    }

    // Fetch sender nickname and recipient FCM token in parallel
    const [senderDoc, recipientDoc] = await Promise.all([
      db.collection('users').doc(senderId).get(),
      db.collection('users').doc(recipientId).get(),
    ]);

    const senderName: string = senderDoc.data()?.nickname ?? 'Unknown';
    const fcmToken: string = recipientDoc.data()?.fcmToken ?? '';

    if (!fcmToken) return;

    const body: string =
      message.type === 'image'
        ? '📷 Photo'
        : (message.text as string) ?? '';

    await messaging.send({
      token: fcmToken,
      notification: {
        title: senderName,
        body,
      },
      data: {
        chatId,
        senderName,
        totalUnread: String(totalUnread),
      },
      apns: {
        payload: {
          aps: {
            badge: totalUnread,
          },
        },
      },
      android: {
        notification: {
          channelId: 'chat_messages',
        },
      },
    });
  });
