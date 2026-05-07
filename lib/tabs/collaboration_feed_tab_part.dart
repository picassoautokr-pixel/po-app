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
    required this.selectedSortOption,
    required this.sortDescending,
  });

  final String regionFilter;
  final String keyword;
  final Set<String> selectedMainCategories;
  final Set<String> subKeySet;
  final bool favoritesOnly;
  final String? selectedSortOption;
  final bool sortDescending;

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
        if (meSnap.hasError) {
          poReportFirestoreSnapshotError(
            'collaboration_feed_me_doc',
            meSnap.error!,
          );
        }
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
              poReportFirestoreSnapshotError(
                'collaboration_feed_requests',
                collabQs.error!,
              );
              return Center(
                child: poFirestoreUserErrorPlaceholder(context),
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

            final searchQ = _poParseSearchQuery(keyword);
            list.sort((a, b) => _compareCollabDocsOrdered(
                  a.data(),
                  b.data(),
                  searchQ: searchQ,
                  sortOption: selectedSortOption,
                  sortDescending: sortDescending,
                  regionFilter: regionFilter,
                  selectedMainCategories: selectedMainCategories,
                  selectedSubLabels: _distinctSubs,
                ));

            if (list.isEmpty) {
              return Center(
                child: Text(
                  !searchQ.isEmpty
                      ? '검색 결과가 없습니다.'
                      : '표시할 공고가 없습니다.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!searchQ.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      '검색 결과 ${list.length}개',
                      style: textTheme.labelLarge?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      poMainShellTabScrollBottomPadding(context),
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) => _collaborationFeedListCard(
                      ctx,
                      list[i],
                      favoriteRequestIds: favoriteRequestIds,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
