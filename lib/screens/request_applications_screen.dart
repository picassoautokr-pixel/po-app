part of '../main.dart';

/// 모집 작성자: 지원 업체 목록.
class RequestApplicationsScreen extends StatefulWidget {
  const RequestApplicationsScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RequestApplicationsScreen> createState() =>
      _RequestApplicationsScreenState();
}

class _RequestApplicationsScreenState extends State<RequestApplicationsScreen> {
  static const Color _accent = Color(0xFF007AFF);

  String? _busyApplicationId;

  Future<void> _accept({
    required BuildContext context,
    required String applicantUid,
    required DocumentReference<Map<String, dynamic>> appRef,
    required DocumentReference<Map<String, dynamic>> reqRef,
  }) async {
    if (_busyApplicationId != null) return;
    setState(() => _busyApplicationId = applicantUid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final reqSnap = await transaction.get(reqRef);
        final rd = reqSnap.data();
        final st =
            _collaborationRequestString(rd?['status']).toLowerCase();
        final sel = _collaborationRequestString(rd?['selectedApplicantUid']);
        if (st == 'matched' &&
            sel.isNotEmpty &&
            sel != applicantUid) {
          throw StateError('matched_other');
        }
        transaction.set(
          appRef,
          <String, Object?>{
            'status': 'accepted',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        transaction.set(
          reqRef,
          <String, Object?>{
            'status': 'matched',
            'selectedApplicantUid': applicantUid,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원을 채택했습니다.')),
      );
      unawaited(createNotification(
        userId: applicantUid.trim(),
        type: 'accepted',
        title: '협업 지원이 채택되었습니다',
        body: '지원한 협업 요청이 채택되었습니다',
        targetId: widget.requestId.trim(),
        targetType: 'request',
      ));
    } on StateError catch (e) {
      if (!context.mounted) return;
      final msg = e.message == 'matched_other'
          ? '이미 다른 업체와 매칭된 공고입니다.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채택 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyApplicationId = null);
    }
  }

  Future<void> _reject({
    required BuildContext context,
    required String applicantUid,
    required DocumentReference<Map<String, dynamic>> appRef,
  }) async {
    if (_busyApplicationId != null) return;
    setState(() => _busyApplicationId = applicantUid);
    try {
      await appRef.set(<String, Object?>{
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원을 거절했습니다.')),
      );
      unawaited(createNotification(
        userId: applicantUid.trim(),
        type: 'rejected',
        title: '협업 지원이 거절되었습니다',
        body: '지원한 협업 요청이 거절되었습니다',
        targetId: widget.requestId.trim(),
        targetType: 'request',
      ));
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('거절 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyApplicationId = null);
    }
  }

  void _openChat({
    required BuildContext context,
    required String ownerUid,
    required String applicantUid,
    required Map<String, dynamic> reqData,
    required String applicantName,
  }) {
    final chatId = collaborationApplicationChatFirestoreId(
      widget.requestId.trim(),
      ownerUid,
      applicantUid,
    );
    if (chatId.isEmpty) return;
    Navigator.of(context).push(poSmoothPushRoute<void>(
      ChatScreen(
        requestId: widget.requestId.trim(),
        partnerUid: applicantUid,
        requestTitle: _collaborationDisplayTitle(reqData),
        partnerDisplayName:
            applicantName.isEmpty ? null : applicantName,
        chatFirestoreDocId: chatId,
      ),
    ));
  }

  void _dialApplicant(BuildContext context, Map<String, dynamic> app) {
    final visible = app['isPhoneVisible'] == true;
    final raw = _collaborationRequestString(app['applicantPhone']);
    if (!visible || raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('전화번호가 공개되지 않았습니다.'),
        ),
      );
      return;
    }
    final sanitized = raw.replaceAll(RegExp(r'[^\d+]'), '');
    _launchBusinessPhone(Uri.parse('tel:$sanitized'));
  }

  int _tsCompare(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ad = a.data()['createdAt'];
    final bd = b.data()['createdAt'];
    if (ad is Timestamp && bd is Timestamp) {
      return bd.compareTo(ad);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final me = FirebaseAuth.instance.currentUser?.uid;

    if (me == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black87,
          title: Text(
            '지원 업체 목록',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Center(
          child: Text(
            '로그인이 필요합니다.',
            style: textTheme.bodyMedium,
          ),
        ),
      );
    }

    final reqRef = FirebaseFirestore.instance
        .collection('collaborationRequests')
        .doc(widget.requestId.trim());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '지원 업체 목록',
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
        stream: reqRef.snapshots(),
        builder: (context, reqSnap) {
          if (reqSnap.hasError) {
            poReportFirestoreSnapshotError(
              'request_applications_req_doc',
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
          if (reqData == null) {
            return const Center(child: Text('공고를 찾을 수 없습니다.'));
          }
          final ownerUid = _collaborationRequestString(reqData['ownerUid']);
          if (ownerUid.isEmpty || ownerUid != me) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '이 공고의 작성자만 지원 목록을 볼 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: reqRef.collection('applications').snapshots(),
            builder: (context, appSnap) {
              if (appSnap.hasError) {
                poReportFirestoreSnapshotError(
                  'request_applications_subcoll',
                  appSnap.error!,
                );
                return Center(
                  child: poFirestoreUserErrorPlaceholder(context),
                );
              }
              final docs = appSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final sorted =
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
                    ..sort(_tsCompare);

              if (sorted.isEmpty) {
                return Center(
                  child: Text(
                    '아직 지원한 업체가 없습니다.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  poFullScreenScrollBottomPadding(context),
                ),
                itemCount: sorted.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (ctx, int index) {
                  final doc = sorted[index];
                  final d = doc.data();
                  final applicantUid =
                      _collaborationRequestString(d['applicantUid']);
                  final name =
                      _collaborationRequestString(d['applicantDisplayName']);
                  if (applicantUid.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final busy = _busyApplicationId == applicantUid;
                  final appCats = collaborationApplicantSearchCategoriesList(d);
                  final catLine =
                      appCats.isEmpty ? '미등록' : appCats.join(' · ');
                  final statusRaw =
                      _collaborationRequestString(d['status']);
                  final stLow = statusRaw.toLowerCase();
                  final canDecide =
                      stLow == 'pending' || stLow.isEmpty;

                  final primary = _collaborationReqMissingStr(
                    d, 'applicantPrimaryCategory',);

                  return DecoratedBox(
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
                          Text(
                            name.isEmpty ? '이름 미등록' : name,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '제안 금액',
                            body: collaborationFormatProposedPrice(
                                d['proposedPrice'],),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '가능 일정',
                            body: _collaborationReqMissingStr(
                                d, 'availableSchedule',),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '준비 가능 자재',
                            body: _collaborationReqMissingStr(
                                d, 'materialOffer',),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '메시지',
                            body: _collaborationReqMissingStr(d, 'message'),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '대표 시공분야',
                            body: primary,
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '세부 시공분야',
                            body: catLine,
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '상태',
                            body: collaborationApplicationStatusKo(statusRaw),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _openChat(
                                            context: context,
                                            ownerUid: ownerUid,
                                            applicantUid: applicantUid,
                                            reqData: reqData,
                                            applicantName: name,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent,
                                    side: BorderSide(
                                        color: _accent.withValues(alpha: 0.45),),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('채팅하기'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _dialApplicant(context, d),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent,
                                    side: BorderSide(
                                        color: _accent.withValues(alpha: 0.45),),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('전화하기'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: busy || !canDecide
                                      ? null
                                      : () => _accept(
                                            context: context,
                                            applicantUid: applicantUid,
                                            appRef: doc.reference,
                                            reqRef: reqRef,
                                          ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(busy ? '처리 중…' : '채택하기'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy || !canDecide
                                      ? null
                                      : () => _reject(
                                            context: context,
                                            applicantUid: applicantUid,
                                            appRef: doc.reference,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(
                                        color: Colors.red.shade200,),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('거절하기'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        ),
      ),
    );
  }
}
