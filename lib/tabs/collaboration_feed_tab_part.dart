part of '../main.dart';

/// 구인·협업 공고 피드 (필터는 [MainShell]에서 전달).
class CollaborationFeedTabBody extends StatelessWidget {
  const CollaborationFeedTabBody({
    super.key,
    required this.regionFilter,
    required this.keyword,
    required this.selectedMainCategories,
    required this.subKeySet,
    required this.favoritesOnly,
  });

  final String regionFilter;
  final String keyword;
  final Set<String> selectedMainCategories;
  final Set<String> subKeySet;
  final bool favoritesOnly;

  Set<String> get _distinctSubs =>
      ServiceCategoryCatalog.distinctSubs(subKeySet);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return Center(
        child: Text(
          '로그인 후 이용할 수 있습니다.',
          style: textTheme.bodyMedium,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, meSnap) {
        final favReqRaw = meSnap.data?.data()?['favoriteRequestIds'];
        final favoriteRequestIds = <String>{
          if (favReqRaw is Iterable)
            for (final e in favReqRaw)
              if (e is String && e.trim().isNotEmpty) e.trim(),
        };

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('collaborationRequests')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, collabQs) {
            if (collabQs.connectionState == ConnectionState.waiting &&
                !collabQs.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (collabQs.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _firestoreLoadErrorHint(collabQs.error!),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                ),
              );
            }

            var list = (collabQs.data?.docs ?? [])
                .where(
                  (QueryDocumentSnapshot<Map<String, dynamic>> q) =>
                      _passesHomeCollaborationFilters(
                    d: q.data(),
                    regionFilter: regionFilter,
                    keywordApplied: keyword,
                    selectedMainCategories: selectedMainCategories,
                    selectedSubLabels: _distinctSubs,
                  ),
                )
                .toList(growable: true);

            if (favoritesOnly) {
              list = list
                  .where((q) => favoriteRequestIds.contains(q.id))
                  .toList(growable: false);
            }

            list.sort((a, b) {
              final primary = _collabSortForSearch(a.data(), b.data());
              if (primary != 0) return primary;
              return _compareRecommendedCollabs(
                a.data(),
                b.data(),
                regionFilter: regionFilter,
                selectedMainCategories: selectedMainCategories,
                selectedSubLabels: _distinctSubs,
              );
            });

            if (list.isEmpty) {
              return Center(
                child: Text(
                  '표시할 공고가 없습니다.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => _collaborationFeedListCard(
                ctx,
                list[i],
                favoriteRequestIds: favoriteRequestIds,
              ),
            );
          },
        );
      },
    );
  }
}
