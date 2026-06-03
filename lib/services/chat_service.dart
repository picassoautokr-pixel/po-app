import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 채팅방 요약 문서를 갱신합니다 (마지막 메시지, 타임스탬프 등).
Future<void> collaborationTouchChatRoomSummary({
  required String chatId,
  required String lastMessage,
  required String senderUid,
}) async {
  final c = chatId.trim();
  if (c.isEmpty) return;
  await FirebaseFirestore.instance.collection('chats').doc(c).set(
    <String, Object?>{
      'lastMessage': lastMessage.trim(),
      'lastMessageSenderUid': senderUid.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}

/// 알림 문서를 생성합니다.
Future<void> createNotification({
  required String userId,
  required String type,
  required String title,
  required String body,
  required String targetId,
  required String targetType,
}) async {
  final uid = userId.trim();
  if (uid.isEmpty) return;
  final ref = FirebaseFirestore.instance.collection('notifications').doc();
  await ref.set(<String, Object?>{
    'notificationId': ref.id,
    'userId': uid,
    'type': type.trim(),
    'title': title.trim(),
    'body': body.trim(),
    'targetId': targetId.trim(),
    'targetType': targetType.trim(),
    'isRead': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// 채팅방 셸 문서가 없으면 생성합니다.
Future<void> collaborationEnsureChatRoomShell({
  required String chatId,
  required String myUid,
  required String partnerUid,
  required String requestId,
  required String requestTitle,
}) async {
  final pu = partnerUid.trim();
  if (chatId.trim().isEmpty || myUid.trim().isEmpty || pu.isEmpty) return;
  await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
    <String, Object?>{
      'chatId': chatId.trim(),
      'participants': <String>[myUid.trim(), pu],
      'requestId': requestId.trim(),
      'partnerUid': pu,
      'requestTitle':
          requestTitle.trim().isEmpty ? '채팅' : requestTitle.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdByCall': false,
      'unreadCountByUser.${myUid.trim()}': 0,
      'unreadCountByUser.$pu': 0,
    },
    SetOptions(merge: true),
  );
}

/// 메시지 발송 직후: 내 미읽음 0, 상대방 미읽음 +1.
Future<void> collaborationApplyOutgoingUnreadCounts({
  required String chatId,
  required String myUid,
  required String partnerUid,
}) async {
  final c = chatId.trim();
  final me = myUid.trim();
  final pu = partnerUid.trim();
  if (c.isEmpty || me.isEmpty || pu.isEmpty || me == pu) return;
  await FirebaseFirestore.instance.collection('chats').doc(c).set(
    <String, Object?>{
      'unreadCountByUser.$me': 0,
      'unreadCountByUser.$pu': FieldValue.increment(1),
    },
    SetOptions(merge: true),
  );
}

/// 채팅방 입장 시 현재 사용자의 미읽음을 0으로 초기화합니다.
Future<void> collaborationResetUnreadForUserInChat({
  required String chatId,
  required String userUid,
}) async {
  final c = chatId.trim();
  final u = userUid.trim();
  if (c.isEmpty || u.isEmpty) return;
  await FirebaseFirestore.instance.collection('chats').doc(c).set(
    <String, Object?>{
      'unreadCountByUser.$u': 0,
    },
    SetOptions(merge: true),
  );
}

/// [chats] 스냅샷에서 현재 사용자 미읽음 합계.
int poChatUnreadTotalForUser(
  QuerySnapshot<Map<String, dynamic>> snap,
  String uid,
) {
  final u = uid.trim();
  if (u.isEmpty) return 0;
  var t = 0;
  for (final d in snap.docs) {
    final raw = d.data()['unreadCountByUser'];
    if (raw is Map<dynamic, dynamic>) {
      final v = raw[u];
      if (v is num) {
        t += v.round().clamp(0, 999999);
      }
    }
  }
  return t;
}

/// 채팅 탭 하단 네비게이션 아이콘 (미읽음 배지 포함).
Widget poChatBottomNavIcon(int unread, {required bool selected}) {
  return Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.topRight,
    children: [
      Icon(
        selected ? Icons.chat_rounded : Icons.chat_bubble_outline_rounded,
      ),
      if (unread > 0)
        Positioned(
          right: -6,
          top: -4,
          child: IgnorePointer(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: unread > 9 ? 5 : 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
    ],
  );
}
