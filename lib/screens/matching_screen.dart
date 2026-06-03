part of '../main.dart';

/// 협업 요청에 대응 가능한 업체 후보 목록 (`users.searchCategories`).
class MatchingScreen extends StatefulWidget {
  const MatchingScreen({
    super.key,
    required this.requestId,
    required this.workType,
    required this.location,
    required this.description,
  });

  /// Firestore 문서 ID(추후 추적용).
  final String requestId;
  final String workType;
  final String location;
  final String description;

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late Future<List<CollaborationMatchingCandidate>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchCollaborationMatchingCandidates(
      workType: widget.workType,
      requestId: widget.requestId,
    );
  }

  Widget _labeledBlock({
    required TextTheme textTheme,
    required String label,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: textTheme.bodyMedium?.copyWith(
            height: 1.45,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 매칭',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () {
              setState(() {
                _future = _fetchCollaborationMatchingCandidates(
                  workType: widget.workType,
                  requestId: widget.requestId,
                );
              });
            },
            icon: Icon(Icons.refresh_rounded, color: _accent),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '작업 종류',
                      body: widget.workType,
                    ),
                    const SizedBox(height: 14),
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '지역',
                      body: widget.location,
                    ),
                    const SizedBox(height: 14),
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '요청 내용',
                      body: widget.description,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final rid = widget.requestId.trim().isEmpty
                      ? 'test_request'
                      : widget.requestId.trim();
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    ChatScreen(
                      requestId: rid,
                      partnerUid: 'test_partner',
                      requestTitle: widget.workType,
                      partnerDisplayName: '테스트 상대',
                    ),
                  ));
                },
                icon: Icon(Icons.chat_bubble_outline_rounded, color: _accent),
                label: const Text('채팅 테스트'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  '추천 업체',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'searchCategories 일치 업체 중 AI 점수 상위 5곳입니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CollaborationMatchingCandidate>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  poReportFirestoreSnapshotError(
                    'collaboration_matching_candidates',
                    snapshot.error!,
                  );
                  return Center(
                    child: poFirestoreUserErrorPlaceholder(context),
                  );
                }

                final rows = snapshot.data ?? <CollaborationMatchingCandidate>[];
                if (rows.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        '조건에 맞는 업체가 아직 없습니다.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    poFullScreenScrollBottomPadding(context),
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _MatchingPartnerCard(
                      doc: row.doc,
                      score: row.score,
                      showRecommendBadge: row.score >= 60,
                      collaborationRequestId: widget.requestId,
                      collaborationRequestTitle: widget.workType,
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

class _MatchingPartnerCard extends StatelessWidget {
  const _MatchingPartnerCard({
    required this.doc,
    required this.score,
    required this.showRecommendBadge,
    required this.collaborationRequestId,
    required this.collaborationRequestTitle,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int score;
  final bool showRecommendBadge;

  /// `collaborationRequests` 문서 ID.
  final String collaborationRequestId;
  /// 협업 요청 타이틀(작업 종류 등 · 채팅 라벨).
  final String collaborationRequestTitle;

  static const Color _accent = Color(0xFF007AFF);

  void _onPhone(BuildContext context, Map<String, dynamic> data) {
    poShowBusinessPhoneSheet(context, data);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final data = doc.data();

    final name = poHomeUserCardTitle(data);
    final regions = _matchingUserRegionsLine(data);
    final primary = _matchingFieldStr(data['primaryCategory']);
    final available = _matchingUserAvailable(data);
    final ratingStr = _matchingFormatAverageRatingDisplay(data);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      letterSpacing: -0.2,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (poBusinessVerificationShowVerifiedBadge(data))
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: poVerifiedCompanyBadgeChip(fontSize: 10),
                  ),
                if (showRecommendBadge)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      '추천',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '즐겨찾기 업체로 추가',
                  onPressed: () => toggleFavoritePartnerUidForMe(
                    context,
                    doc.id,
                  ),
                  icon: Icon(
                    Icons.star_outline_rounded,
                    color: _accent,
                  ),
                ),
                if (available)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        '준비 가능',
                        style: textTheme.labelSmall?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '추천 점수 $score',
              style: textTheme.titleSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.handyman_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    primary.isEmpty ? '미등록' : primary,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    regions == '-' || regions.isEmpty ? '미등록' : regions,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star_rounded,
                    size: 18, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(
                  '평점 $ratingStr',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      runWithBriefLoading(context, () {
                        if (!context.mounted) return;
                        final rid = collaborationRequestId.trim().isEmpty
                            ? 'test_request'
                            : collaborationRequestId.trim();
                        final pid = doc.id.trim().isEmpty
                            ? 'test_partner'
                            : doc.id.trim();
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          ChatScreen(
                            requestId: rid,
                            partnerUid: pid,
                            requestTitle: collaborationRequestTitle,
                            partnerDisplayName: name,
                          ),
                        ));
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('채팅하기'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _onPhone(context, data),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('전화하기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
