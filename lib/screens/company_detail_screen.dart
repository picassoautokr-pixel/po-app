part of '../main.dart';

/// 홈 업체 카드에서 진입하는 업체 상세 프로필.
class CompanyDetailScreen extends StatelessWidget {
  const CompanyDetailScreen({
    super.key,
    required this.partnerUid,
    required this.userData,
  });

  final String partnerUid;
  final Map<String, dynamic> userData;

  static const Color _accent = Color(0xFF007AFF);

  void _requireLoginSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
  }

  void _onPhone(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    poShowBusinessPhoneSheet(context, userData);
  }

  void _onChat(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    final name = poHomeUserCardTitle(userData);
    runWithBriefLoading(context, () {
      if (!context.mounted) return;
      Navigator.of(context).push(poSmoothPushRoute<void>(
        ChatScreen(
          requestId: 'direct',
          partnerUid: partnerUid,
          requestTitle: '$name · 문의',
          partnerDisplayName: name,
        ),
      ));
    });
  }

  void _onFavorite(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    toggleFavoritePartnerUidForMe(context, partnerUid);
  }

  Widget _infoRow(TextTheme textTheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions(
    BuildContext context, {
    required String? meUid,
    required bool isFavorite,
  }) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _onPhone(context, meUid),
                    icon: Icon(Icons.call_outlined, color: _accent, size: 18),
                    label: const Text('전화하기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _onChat(context, meUid),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('채팅하기'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _onFavorite(context, meUid),
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _accent,
              ),
              label: Text(isFavorite ? '즐겨찾기 해제' : '즐겨찾기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final d = userData;

    final infoBody = DecoratedBox(
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
            _infoRow(
              textTheme,
              '표시 이름',
              _companyProfileFieldOrMissing(d, 'displayName'),
            ),
            _infoRow(
              textTheme,
              '사업자명',
              _companyProfileFieldOrMissing(d, 'businessName'),
            ),
            _infoRow(
              textTheme,
              '매장명',
              _companyProfileFieldOrMissing(d, 'shopName'),
            ),
            _infoRow(
              textTheme,
              '대표자명',
              _companyProfileFieldOrMissing(d, 'ownerName'),
            ),
            _infoRow(
              textTheme,
              '지역',
              _companyProfileRegionsLine(d),
            ),
            _infoRow(
              textTheme,
              '대표 시공분야',
              _companyProfileFieldOrMissing(d, 'primaryCategory'),
            ),
            _infoRow(
              textTheme,
              '메인 카테고리',
              _companyProfileListLine(d, 'mainCategories'),
            ),
            _infoRow(
              textTheme,
              '세부 시공분야',
              _companyProfileListLine(d, 'searchCategories'),
            ),
            _infoRow(
              textTheme,
              '가성비 구간',
              _companyProfileFieldOrMissing(d, 'priceRange'),
            ),
            _infoRow(
              textTheme,
              '응답 속도',
              _companyProfileFieldOrMissing(d, 'responseSpeed'),
            ),
            _infoRow(
              textTheme,
              '전화번호',
              _companyProfileFieldOrMissing(d, 'phoneNumber'),
            ),
            _infoRow(
              textTheme,
              '매장 전화',
              _companyProfileFieldOrMissing(d, 'storePhone'),
            ),
            _infoRow(
              textTheme,
              '홈페이지',
              _companyProfileFieldOrMissing(d, 'homepageUrl'),
            ),
            _infoRow(
              textTheme,
              '블로그',
              _companyProfileFieldOrMissing(d, 'blogUrl'),
            ),
            _infoRow(
              textTheme,
              '사업자 인증',
              _companyProfileLicenseStatus(d),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 프로필',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                poFullScreenScrollBottomPadding(context),
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        poHomeUserCardTitle(d),
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (poBusinessVerificationShowVerifiedBadge(d)) ...[
                      const SizedBox(width: 8),
                      poVerifiedCompanyBadgeChip(fontSize: 11),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                infoBody,
                const SizedBox(height: 28),
                Text(
                  '마감 디테일 약속',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _CompanyFinishDetailsSection(partnerUid: partnerUid),
              ],
            ),
          ),
          if (me != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(me)
                  .snapshots(),
              builder: (context, snap) {
                final raw = snap.data?.data()?['favoritePartnerUids'];
                final fav = <String>{
                  if (raw is Iterable)
                    for (final e in raw)
                      if (e is String && e.trim().isNotEmpty) e.trim(),
                };
                final isFav = fav.contains(partnerUid);
                return _bottomActions(
                  context,
                  meUid: me,
                  isFavorite: isFav,
                );
              },
            )
          else
            _bottomActions(context, meUid: null, isFavorite: false),
        ],
        ),
      ),
    );
  }
}

String collaborationChatFirestoreId(String requestId, String partnerUid) =>
    '${requestId.trim()}_${partnerUid.trim()}';

bool _poChatMessageIsDeleted(Map<String, dynamic> data) =>
    data['isDeleted'] == true;

/// 갤러리 스와이프용: 완료된 이미지 URL만.
bool _poChatMessageIsGalleryImage(Map<String, dynamic> data) {
  if (_poChatMessageIsDeleted(data)) return false;
  if ((data['type'] as String?)?.trim() != 'image') return false;
  final url = (data['imageUrl'] as String?)?.trim() ?? '';
  if (url.isEmpty) return false;
  final st = data['status'];
  if (st is String) return st == 'complete';
  return true;
}

List<String> _poChatGalleryImageUrls(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final out = <String>[];
  for (final d in docs) {
    if (!_poChatMessageIsGalleryImage(d.data())) continue;
    final u = (d.data()['imageUrl'] as String?)?.trim() ?? '';
    if (u.isNotEmpty) out.add(u);
  }
  return out;
}

int _poChatGalleryStartIndex(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String tappedDocId,
) {
  var idx = 0;
  var start = 0;
  var found = false;
  for (final d in docs) {
    if (!_poChatMessageIsGalleryImage(d.data())) continue;
    if (d.id == tappedDocId) {
      start = idx;
      found = true;
    }
    idx++;
  }
  return found ? start : 0;
}
