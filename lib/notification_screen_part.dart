part of 'main.dart';

/// Firestore `notifications/{notificationId}` 필드:
/// notificationId, userId, type, title, body, targetId, targetType,
/// isRead, createdAt, readAt

Future<void> _markNotificationRead(String notificationId) async {
  final id = notificationId.trim();
  if (id.isEmpty) return;
  try {
    await FirebaseFirestore.instance.collection('notifications').doc(id).update(
      <String, Object?>{
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      },
    );
  } on Object {
    // 읽음 처리 실패는 조용히 무시 (목록은 다시 시도 가능)
  }
}

/// 알림 문서의 이동 라우트: 신규 [targetType] 또는 레거시 [type].
String _notificationEffectiveTargetType(Map<String, dynamic>? data) {
  if (data == null) return '';
  final tt = _matchingFieldStr(data['targetType']).trim().toLowerCase();
  if (tt.isNotEmpty) return tt;
  final ty = _matchingFieldStr(data['type']).trim().toLowerCase();
  if (ty == 'chat') return 'chat';
  if (ty == 'review') return 'review';
  return 'request';
}

Future<void> _navigateFromNotificationDoc(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || !context.mounted) return;

  final targetId =
      (_matchingFieldStr(doc.data()['targetId'])).trim();
  final route = _notificationEffectiveTargetType(doc.data());

  if (targetId.isEmpty) {
    return;
  }

  switch (route) {
    case 'chat':
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(targetId)
          .get();
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
      var partnerUid = _matchingFieldStr(d['partnerUid']);
      if (partnerUid.isEmpty) {
        partnerUid = _chatPartnerUidOrInfer(d, uid);
      }
      final title = _collaborationRequestString(d['requestTitle']);
      if (!context.mounted) return;
      if (partnerUid.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('대화 상대 정보를 찾을 수 없습니다.')),
        );
        return;
      }
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
    case 'review':
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
      final titleText = _collaborationDisplayTitle(reqSnap.data()!);
      await Navigator.of(context).push<void>(
        poSmoothPushRoute<void>(
          ReviewScreen(
            requestTitle: titleText.isEmpty ? targetId : titleText,
          ),
        ),
      );
      break;
    case 'request':
    default:
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
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            poReportFirestoreSnapshotError(
              'notifications_screen',
              snapshot.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
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
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              0,
              poFullScreenScrollBottomPadding(context),
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (ctx, index) {
              final doc = docs[index];
              final data = doc.data();
              final title = (data['title'] as String?)?.trim() ?? '알림';
              final body = (data['body'] as String?)?.trim() ?? '';
              final isRead = data['isRead'] == true;
              final created = _formatCreatedAt(data['createdAt']);
              final targetId =
                  (_matchingFieldStr(data['targetId'])).trim();

              return Material(
                color: isRead ? Colors.white : _accent.withValues(alpha: 0.06),
                child: InkWell(
                  onTap: () async {
                    await _markNotificationRead(doc.id);
                    if (!context.mounted) return;
                    if (targetId.isEmpty) return;
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
                              if (targetId.isEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '(연결 화면 없음)',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade500,
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
      ),
    );
  }
}
