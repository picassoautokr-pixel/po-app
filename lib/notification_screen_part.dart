part of 'main.dart';

/// Firestore `notifications/{notificationId}` 권장 필드:
/// - userId (String): 받는 사람 uid
/// - type: "chat" | "apply" | "accept" | "reject"
/// - title, body (String)
/// - targetId: chat 유형이면 `chats` 문서 id, 나머지는 `collaborationRequests` 문서 id
/// - isRead (bool)
/// - createdAt (Timestamp) — 쿼리용, `userId` + `createdAt` 내림차순 색인 필요

Future<void> _markNotificationRead(String notificationId) async {
  final id = notificationId.trim();
  if (id.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(id)
        .update(<String, Object?>{'isRead': true});
  } on Object {
    // 읽음 처리 실패는 조용히 무시 (목록은 다시 시도 가능)
  }
}

Future<void> _navigateFromNotificationDoc(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || !context.mounted) return;

  final type = (doc.data()['type'] as String?)?.trim() ?? '';
  final targetId = (doc.data()['targetId'] as String?)?.trim() ?? '';

  if (targetId.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이동할 대상이 없습니다.')),
    );
    return;
  }

  switch (type) {
    case 'chat':
      final snap =
          await FirebaseFirestore.instance.collection('chats').doc(targetId).get();
      if (!context.mounted) return;
      if (!snap.exists || snap.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방을 찾을 수 없습니다.')),
        );
        return;
      }
      final d = snap.data()!;
      final requestId = _collaborationRequestString(d['requestId']);
      if (requestId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅 연결 정보가 없습니다.')),
        );
        return;
      }
      final partnerUid = _chatPartnerUidOrInfer(d, uid);
      if (partnerUid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('대화 상대 정보를 찾을 수 없습니다.')),
        );
        return;
      }
      final title = _collaborationRequestString(d['requestTitle']);
      await Navigator.of(context).push<void>(
        poSmoothPushRoute<void>(
          ChatScreen(
            requestId: requestId,
            partnerUid: partnerUid,
            requestTitle: title.isEmpty ? '채팅' : title,
            chatFirestoreDocId: targetId,
          ),
        ),
      );
      break;
    case 'apply':
    case 'accept':
    case 'reject':
      final reqSnap = await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(targetId)
          .get();
      if (!context.mounted) return;
      if (!reqSnap.exists || reqSnap.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공고를 찾을 수 없습니다.')),
        );
        return;
      }
      _openCollaborationRequestDetailFromDoc(context, reqSnap);
      break;
    default:
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알 수 없는 알림 유형입니다. ($type)')),
      );
  }
}

/// Firestore `notifications` 컬렉션 문서를 표시합니다.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  static const Color _accent = Color(0xFF007AFF);

  String _formatCreatedAt(dynamic v) {
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          surfaceTintColor: Colors.transparent,
          title: const Text('알림'),
        ),
        body: const Center(child: Text('로그인 후 이용할 수 있습니다.')),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '알림',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  '알림을 불러오지 못했습니다.\n${snapshot.error}\n\n'
                  'Firestore에 notifications 컬렉션에 대한 userId + createdAt 복합 색인이 필요할 수 있습니다.',
                  style: textTheme.bodySmall?.copyWith(height: 1.45),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (docs.isEmpty) {
            return Center(
              child: Text(
                '알림이 없습니다.',
                style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            itemCount: docs.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (ctx, index) {
              final doc = docs[index];
              final data = doc.data();
              final title = (data['title'] as String?)?.trim() ?? '알림';
              final body = (data['body'] as String?)?.trim() ?? '';
              final isRead = data['isRead'] == true;
              final created = _formatCreatedAt(data['createdAt']);

              return Material(
                color: isRead ? Colors.white : _accent.withValues(alpha: 0.06),
                child: InkWell(
                  onTap: () async {
                    await _markNotificationRead(doc.id);
                    if (!context.mounted) return;
                    await _navigateFromNotificationDoc(context, doc);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2, right: 12),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isRead ? Colors.transparent : _accent,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              if (body.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  body,
                                  style: textTheme.bodyMedium?.copyWith(
                                    height: 1.4,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                              if (created.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  created,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
