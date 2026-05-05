part of '../main.dart';

/// 내가 작성한 구인·협업 공고만 표시 (새 공고는 [MainShell] 상단 버튼).
class MyRequestsTabScreen extends StatelessWidget {
  const MyRequestsTabScreen({super.key});

  static int _statusOrderKey(String statusRaw) {
    final s = collaborationDisplayStatusKo(
      statusRaw.trim().isEmpty ? 'open' : statusRaw,
    );
    const order = <String>[
      '모집중',
      '채택됨',
      '진행중',
      '완료',
      '마감',
      '취소',
    ];
    final i = order.indexOf(s);
    return i >= 0 ? i : order.length;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text('로그인 후 이용할 수 있습니다.'),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('collaborationRequests')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, collabSnap) {
          if (collabSnap.connectionState == ConnectionState.waiting &&
              !collabSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (collabSnap.hasError) {
            return Center(
              child: Text(
                '불러오기 실패:\n${collabSnap.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = collabSnap.data?.docs ?? [];
          final mine = docs
              .where(
                (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                    _collaborationRequestString(d.data()['ownerUid']) == uid,
              )
              .toList(growable: false);

          mine.sort((a, b) {
            final sa = _collaborationRequestString(a.data()['status']);
            final sb = _collaborationRequestString(b.data()['status']);
            final oa = _statusOrderKey(sa);
            final ob = _statusOrderKey(sb);
            if (oa != ob) return oa.compareTo(ob);
            final da =
                _firestoreAsDateTime(a.data()['createdAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            final db =
                _firestoreAsDateTime(b.data()['createdAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (mine.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '등록한 모집·협업 공고가 없습니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: mine.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              return _collaborationCardFromFirestoreDoc(
                ctx,
                mine[i],
                showCollaborationStatus: true,
              );
            },
          );
        },
      ),
    );
  }
}
