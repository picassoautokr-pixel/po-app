part of '../main.dart';

/// 타 사용자 모집글: 의뢰인 정보 확인·채팅 진입 등.
class PartnerRequestDetailScreen extends StatefulWidget {
  const PartnerRequestDetailScreen({
    super.key,
    required this.requestId,
    required this.ownerUid,
    this.ownerEmailFromRequest,
  });

  final String requestId;
  final String ownerUid;
  final String? ownerEmailFromRequest;

  @override
  State<PartnerRequestDetailScreen> createState() =>
      _PartnerRequestDetailScreenState();
}

class _PartnerRequestDetailScreenState extends State<PartnerRequestDetailScreen> {
  static const Color _accent = Color(0xFF007AFF);

  bool _applicationActionBusy = false;

  bool _loadingOwner = true;
  bool _favorited = false;
  bool _favoriteBusy = false;
  String _ownerDisplayName = '불러오는 중…';
  String _ownerRegions = '미등록';
  String _ownerBizShop = '미등록';
  String _ownerPrimaryCat = '미등록';
  String _ownerPhoneRaw = '';
  Map<String, dynamic> _ownerData = const {};

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
    _loadFavoriteRequestInterest();
  }

  Future<void> _loadFavoriteRequestInterest() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final rid = widget.requestId.trim();
    if (me == null || rid.isEmpty || !mounted) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(me).get();
      final raw = snap.data()?['favoriteRequestIds'];
      final set = raw is Iterable
          ? raw
              .whereType<String>()
              .map((String s) => s.trim())
              .where((String s) => s.isNotEmpty)
              .toSet()
          : <String>{};
      if (!mounted) return;
      setState(() => _favorited = set.contains(rid));
    } on Object {
      if (!mounted) return;
    }
  }

  Future<void> _toggleFavoriteRequestInterest() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final rid = widget.requestId.trim();
    if (me == null || rid.isEmpty || _favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    try {
      final willAdd = !_favorited;
      await FirebaseFirestore.instance.collection('users').doc(me).set(
            <String, Object?>{
              'favoriteRequestIds': willAdd
                  ? FieldValue.arrayUnion([rid])
                  : FieldValue.arrayRemove([rid]),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      setState(() => _favorited = willAdd);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willAdd ? '관심 모집에 추가했습니다.' : '관심 모집을 해제했습니다.',
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _loadOwnerProfile() async {
    final uid = widget.ownerUid.trim();
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingOwner = false;
          _ownerDisplayName = '의뢰업체 정보 없음';
          _ownerRegions = '미등록';
          _ownerBizShop = '미등록';
          _ownerPrimaryCat = '미등록';
          _ownerPhoneRaw = '';
        });
      }
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (!mounted) return;
      setState(() {
        _loadingOwner = false;
        if (data == null) {
          final fbEmail = widget.ownerEmailFromRequest?.trim() ?? '';
          _ownerDisplayName =
              fbEmail.isNotEmpty ? fbEmail : '등록 프로필 없음';
          _ownerRegions = '미등록';
          _ownerBizShop = '미등록';
          _ownerPrimaryCat = '미등록';
          _ownerPhoneRaw = '';
          _ownerData = const {};
        } else {
          _ownerDisplayName = poHomeUserCardTitle(data);
          final regLine = _matchingUserRegionsLine(data);
          _ownerRegions =
              regLine == '-' || regLine.isEmpty ? '미등록' : regLine;
          final bn = _matchingFieldStr(data['businessName']);
          final sn = _matchingFieldStr(data['shopName']);
          _ownerBizShop = [bn, sn]
              .where((String s) => s.isNotEmpty)
              .join(' · ');
          if (_ownerBizShop.isEmpty) _ownerBizShop = '미등록';
          final pc = _matchingFieldStr(data['primaryCategory']);
          _ownerPrimaryCat = pc.isEmpty ? '미등록' : pc;
          _ownerPhoneRaw = poUserPrimaryPhone(data);
          _ownerData = data;
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingOwner = false;
        _ownerDisplayName = '정보를 불러오지 못했습니다';
        _ownerRegions = '미등록';
        _ownerBizShop = '미등록';
        _ownerPrimaryCat = '미등록';
        _ownerPhoneRaw = '';
        _ownerData = const {};
      });
    }
  }

  void _dialOwnerPhone() {
    poShowBusinessPhoneSheet(context, _ownerData);
  }

  Future<void> _confirmCancelApplication(
    DocumentReference<Map<String, dynamic>> appRef,
  ) async {
    if (_applicationActionBusy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지원 취소'),
        content: const Text('이 공고 지원을 취소할까요? 취소 후에는 상태만 \'취소됨\'으로 바뀌며 삭제되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('닫기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('지원 취소'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _applicationActionBusy = true);
    try {
      await appRef.set(<String, Object?>{
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원을 취소했습니다.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('취소 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _applicationActionBusy = false);
    }
  }

  Widget _myApplicationSection(
    TextTheme textTheme,
    Map<String, dynamic>? reqData,
  ) {
    final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (meUid.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('로그인이 필요합니다.')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('협업 가능'),
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .collection('applications')
          .doc(meUid)
          .snapshots(),
      builder: (context, appSnap) {
        if (appSnap.hasError) {
          poReportFirestoreSnapshotError(
            'partner_my_application_doc',
            appSnap.error!,
          );
          return poFirestoreUserErrorPlaceholder(
            context,
            verticalPadding: 12,
          );
        }
        final hasDoc =
            appSnap.hasData && appSnap.data != null && appSnap.data!.exists;

        void openApplyForm() {
          Navigator.of(context).push(poSmoothPushRoute<void>(
            ApplyToRequestScreen(requestId: widget.requestId.trim()),
          ));
        }

        if (!hasDoc) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: openApplyForm,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('협업 가능'),
              ),
              const SizedBox(height: 10),
            ],
          );
        }

        final appMap = appSnap.data!.data() ?? <String, dynamic>{};
        final appStatus =
            _collaborationRequestString(appMap['status']).toLowerCase();
        final statusLine = collaborationMyApplicantCombinedStatusKo(appMap);
        final appliedAt =
            _firestoreAsDateTime(appMap['createdAt']) ??
                _firestoreAsDateTime(appMap['updatedAt']);
        final appliedAtStr = appliedAt == null
            ? '-'
            : '${appliedAt.year}.${appliedAt.month.toString().padLeft(2, '0')}.${appliedAt.day.toString().padLeft(2, '0')} '
                '${appliedAt.hour.toString().padLeft(2, '0')}:'
                '${appliedAt.minute.toString().padLeft(2, '0')}';

        Widget actionRow() {
          if (_applicationActionBusy) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }

          if (appStatus == 'pending') {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: openApplyForm,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('지원 수정'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _confirmCancelApplication(appSnap.data!.reference),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('지원 취소'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            );
          }

          if (appStatus == 'cancelled' || appStatus == 'rejected') {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: openApplyForm,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                child: const Text('다시 지원하기'),
                ),
                const SizedBox(height: 10),
              ],
            );
          }

          if (appStatus == 'accepted') {
            return const SizedBox.shrink();
          }

          return const SizedBox(height: 4);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accent.withValues(alpha: 0.22)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '내 지원',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      statusLine,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '제안 금액',
                      body: collaborationFormatProposedPrice(
                        appMap['proposedPrice'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '가능 일정',
                      body:
                          _collaborationReqMissingStr(appMap, 'availableSchedule'),
                    ),
                    const SizedBox(height: 10),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '자재 조건·준비',
                      body: _collaborationReqMissingStr(appMap, 'materialOffer'),
                    ),
                    const SizedBox(height: 10),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '메시지',
                      body: _collaborationReqMissingStr(appMap, 'message'),
                    ),
                    const SizedBox(height: 10),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '지원 상태 (문서)',
                      body: collaborationApplicationStatusKo(appMap['status']),
                    ),
                    const SizedBox(height: 10),
                    _collaborationDetailLabeledBlock(
                      textTheme: textTheme,
                      label: '지원일',
                      body: appliedAtStr,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            actionRow(),
          ],
        );
      },
    );
  }

  Widget _ownerCard(TextTheme textTheme) {
    final emailLine = widget.ownerEmailFromRequest?.trim() ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '의뢰업체',
              style: textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingOwner)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else ...[
              Text(
                _ownerDisplayName,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              if (emailLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  emailLine,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '사업자·매장',
                body: _ownerBizShop,
              ),
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '대표 시공분야',
                body: _ownerPrimaryCat,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _ownerRegions,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '연락처',
                body: _ownerPhoneRaw.trim().isEmpty ? '미등록' : _ownerPhoneRaw,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ownerUid = widget.ownerUid.trim();
    final chatPartnerUid =
        ownerUid.isNotEmpty ? ownerUid : 'test_partner';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 요청 상세',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('collaborationRequests')
              .doc(widget.requestId)
              .snapshots(),
          builder: (context, reqSnap) {
            if (reqSnap.hasError) {
              poReportFirestoreSnapshotError(
                'partner_request_detail_doc',
                reqSnap.error!,
              );
              return Center(
                child: poFirestoreUserErrorPlaceholder(context),
              );
            }
            if (reqSnap.connectionState == ConnectionState.waiting &&
                !reqSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final reqData = reqSnap.data?.data();
            final chatTitle = reqData == null
                ? '협업 요청'
                : _collaborationDisplayTitle(reqData);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                poFullScreenScrollBottomPadding(context),
              ),
              children: [
              _collaborationRequestDetailFieldsCard(
                textTheme: textTheme,
                data: reqData,
                showStatus: true,
              ),
              const SizedBox(height: 16),
              _myApplicationSection(
                  textTheme, reqData),
              const SizedBox(height: 16),
              _ownerCard(textTheme),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _loadingOwner ? null : _dialOwnerPhone,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('전화하기'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  if (meUid.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('로그인이 필요합니다.')),
                    );
                    return;
                  }
                  final triChatId = collaborationApplicationChatFirestoreId(
                    widget.requestId,
                    chatPartnerUid,
                    meUid,
                  );
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    ChatScreen(
                      requestId: widget.requestId,
                      partnerUid: chatPartnerUid,
                      requestTitle: chatTitle,
                      partnerDisplayName: _loadingOwner ||
                              _ownerDisplayName == '불러오는 중…'
                          ? null
                          : (_ownerDisplayName.isEmpty
                              ? null
                              : _ownerDisplayName),
                      chatFirestoreDocId:
                          triChatId.isEmpty ? null : triChatId,
                    ),
                  ));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('채팅 문의'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _favoriteBusy ? null : _toggleFavoriteRequestInterest,
                icon: Icon(
                  _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _accent,
                ),
                label: Text(_favoriteBusy ? '처리 중…' : '즐겨찾기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}
