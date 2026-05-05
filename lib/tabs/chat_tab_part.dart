part of '../main.dart';

bool _chatUidIterableContains(dynamic raw, String uid) {
  if (raw is! Iterable) return false;
  return raw.any((dynamic e) => e == uid);
}

bool _chatPassesPrimaryFilters(
    Map<String, dynamic>? data, String myUid,) {
  if (data == null) return false;
  if (!_chatUidIterableContains(data['participants'], myUid)) return false;
  if (_chatUidIterableContains(data['hiddenFor'], myUid)) return false;
  final cbc = data['createdByCall'] == true;
  final hm = data['hasMessages'] == true;
  if (cbc && !hm) return false;
  return true;
}

bool _chatPassesHiddenList(Map<String, dynamic>? data, String myUid) {
  if (data == null) return false;
  if (!_chatUidIterableContains(data['participants'], myUid)) return false;
  return _chatUidIterableContains(data['hiddenFor'], myUid);
}

String _chatPartnerUidOrInfer(Map<String, dynamic> data, String myUid) {
  final p = data['partnerUid'];
  if (p is String && p.trim().isNotEmpty) return p.trim();
  final raw = data['participants'];
  if (raw is Iterable) {
    for (final dynamic e in raw) {
      if (e is String && e.isNotEmpty && e != myUid) return e;
    }
  }
  return '';
}

String _chatFormatUpdatedAt(dynamic ts) {
  if (ts is Timestamp) {
    final d = ts.toDate();
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

Future<void> _chatHideRoomForUid(String chatDocId, String uid) =>
    FirebaseFirestore.instance.collection('chats').doc(chatDocId).set(
          <String, Object?>{
            'hiddenFor': FieldValue.arrayUnion([uid.trim()]),
          },
          SetOptions(merge: true),
        );

Future<void> _chatUnhideRoomForUid(String chatDocId, String uid) =>
    FirebaseFirestore.instance.collection('chats').doc(chatDocId).set(
          <String, Object?>{
            'hiddenFor': FieldValue.arrayRemove([uid.trim()]),
          },
          SetOptions(merge: true),
        );

class ChatTabScreen extends StatefulWidget {
  const ChatTabScreen({super.key});

  @override
  State<ChatTabScreen> createState() => _ChatTabScreenState();
}

class _ChatTabScreenState extends State<ChatTabScreen> {
  static const Color _accent = Color(0xFF007AFF);

  bool _showHiddenList = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            '로그인 후 이용할 수 있습니다.',
            style: textTheme.bodyMedium,
          ),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Text(
                    '채팅',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    tooltip: '알림',
                    onPressed: () => _openPoNotifications(context),
                    icon: Icon(Icons.notifications_outlined, color: Colors.grey.shade800),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _showHiddenList = !_showHiddenList);
                    },
                    icon: Icon(
                      _showHiddenList
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: _accent,
                      size: 20,
                    ),
                    label: Text(
                      _showHiddenList ? '일반 목록' : '숨김 리스트 보기',
                      style: textTheme.labelLarge?.copyWith(color: _accent),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SelectableText(
                          '목록 로드 오류 (${snapshot.error}).\n'
                          'Firestore에 participants·updatedAt 복합 색인이 필요할 수 있습니다.',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade800,
                            height: 1.45,
                          ),
                        ),
                      ),
                    );
                  }

                  final all = snapshot.data?.docs ?? [];
                  final filtered = all
                      .where(
                        (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                            _showHiddenList
                                ? _chatPassesHiddenList(d.data(), uid)
                                : _chatPassesPrimaryFilters(d.data(), uid),
                      )
                      .toList(growable: false);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _showHiddenList
                            ? '숨긴 채팅이 없습니다.'
                            : '표시할 채팅이 없습니다.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (ctx, index) {
                      final doc = filtered[index];
                      final data = doc.data();
                      final title =
                          _collaborationRequestString(data['requestTitle']);
                      final lm =
                          _collaborationRequestString(data['lastMessage']);
                      final timeStr = _chatFormatUpdatedAt(data['updatedAt']);
                      final partnerUid = _chatPartnerUidOrInfer(data, uid);

                      final displayTitle =
                          title.isEmpty ? '대화방' : title;

                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor:
                              _accent.withValues(alpha: 0.12),
                          foregroundColor: _accent,
                          child: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _accent),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                displayTitle,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          lm.isEmpty ? '메시지 없음' : lm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            try {
                              if (v == 'hide') {
                                await _chatHideRoomForUid(doc.id, uid);
                              } else if (v == 'unhide') {
                                await _chatUnhideRoomForUid(doc.id, uid);
                              }
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    v == 'hide'
                                        ? '채팅을 숨겼습니다.'
                                        : '목록에 다시 표시했습니다.',
                                  ),
                                ),
                              );
                            } on Object catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('실패: $e')),
                              );
                            }
                          },
                          itemBuilder: (ctx2) => _showHiddenList
                              ? const [
                                  PopupMenuItem(
                                    value: 'unhide',
                                    child: Text('다시 보기'),
                                  ),
                                ]
                              : const [
                                  PopupMenuItem(
                                    value: 'hide',
                                    child: Text('숨기기 · 나가기'),
                                  ),
                                ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(poSmoothPushRoute<void>(
                            ChatScreen(
                              requestId:
                                  _collaborationRequestString(data['requestId']),
                              partnerUid: partnerUid,
                              requestTitle: displayTitle == '대화방'
                                  ? ''
                                  : displayTitle,
                              chatFirestoreDocId: doc.id,
                            ),
                          ));
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
