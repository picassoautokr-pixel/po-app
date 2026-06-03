part of '../main.dart';

/// 모집글 작성자: 관리 메뉴 및 추천 업체 매칭 진입.
class OwnerRequestDetailScreen extends StatefulWidget {
  const OwnerRequestDetailScreen({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<OwnerRequestDetailScreen> createState() =>
      _OwnerRequestDetailScreenState();
}

class _OwnerRequestDetailScreenState extends State<OwnerRequestDetailScreen> {
  static const Color _accent = Color(0xFF007AFF);

  bool _closing = false;
  bool _workBusy = false;

  String _requestStatusLower(Map<String, dynamic>? data) => data == null
      ? ''
      : _collaborationRequestString(data['status']).toLowerCase();

  Future<void> _onStartWork() async {
    if (_workBusy) return;
    setState(() => _workBusy = true);
    try {
      final reqRef = FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim());
      final cur = await reqRef.get();
      final partner = _collaborationRequestString(
        cur.data()?['selectedApplicantUid'],
      ).trim();
      if (partner.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채택된 업체가 없습니다.')),
        );
        return;
      }
      await reqRef.update(<String, Object?>{
        'status': 'in_progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      unawaited(createNotification(
        userId: partner,
        type: 'status',
        title: '작업이 시작되었습니다',
        body: '협업 작업이 시작 상태로 변경되었습니다',
        targetId: widget.requestId.trim(),
        targetType: 'request',
      ));
      if (!mounted) return;
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('작업 시작 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _workBusy = false);
    }
  }

  Future<void> _onCompleteWorkAndEvaluate(Map<String, dynamic> data) async {
    if (_workBusy) return;
    final partner =
        _collaborationRequestString(data['selectedApplicantUid']).trim();
    if (partner.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('채택된 업체 정보를 찾을 수 없습니다.'),
        ),
      );
      return;
    }

    setState(() => _workBusy = true);
    try {
      await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .update(<String, Object?>{
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      unawaited(createNotification(
        userId: partner,
        type: 'status',
        title: '작업이 완료되었습니다',
        body: '협업 작업이 완료되었습니다',
        targetId: widget.requestId.trim(),
        targetType: 'request',
      ));
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        poSmoothPushRoute<void>(
          EvaluationScreen(
            requestId: widget.requestId.trim(),
            targetUid: partner,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('작업 완료 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _workBusy = false);
    }
  }

  Future<void> _closeRecruitment() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId)
          .update(<String, Object?>{
        'status': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집을 마감했습니다.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('마감 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  bool _docStatusClosed(Map<String, dynamic>? data) {
    if (data == null) return false;
    return _collaborationRequestString(data['status']).toLowerCase() ==
        'closed';
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final padding =
        const EdgeInsets.symmetric(vertical: 14);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: padding,
          shape: shape,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _accent,
        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
        padding: padding,
        shape: shape,
      ),
      child: Text(label),
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
          '내 모집글 관리',
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
          builder: (context, snap) {
          if (snap.hasError) {
            poReportFirestoreSnapshotError(
              'owner_manage_request_doc',
              snap.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data?.data();
          if (data == null && snap.hasData) {
            return Center(
              child: Text(
                '공고가 삭제되었거나 없습니다.',
                style: textTheme.bodyMedium,
              ),
            );
          }

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
                data: data,
                showStatus: true,
              ),
              const SizedBox(height: 20),
              if (_requestStatusLower(data) == 'matched') ...[
                _actionButton(
                  label: _workBusy ? '처리 중…' : '작업 시작',
                  filled: true,
                  onPressed: _workBusy ? null : _onStartWork,
                ),
                const SizedBox(height: 10),
              ],
              if (_requestStatusLower(data) == 'in_progress') ...[
                _actionButton(
                  label: _workBusy ? '처리 중…' : '작업 완료',
                  filled: true,
                  onPressed: _workBusy || data == null
                      ? null
                      : () => _onCompleteWorkAndEvaluate(data),
                ),
                const SizedBox(height: 10),
              ],
              _actionButton(
                label: '지원 업체 보기',
                onPressed: () {
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    RequestApplicationsScreen(requestId: widget.requestId),
                  ));
                },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '추천 업체 보기',
                filled: true,
                onPressed: data == null
                    ? null
                    : () {
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          MatchingScreen(
                            requestId: widget.requestId,
                            workType: _collaborationDisplayTitle(data),
                            location: _collaborationRequestString(data['location']),
                            description:
                                _collaborationRequestString(data['description']),
                          ),
                        ));
                      },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '모집글 수정',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('모집글 수정은 준비 중입니다.')),
                  );
                },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: _closing ? '처리 중…' : '모집 마감',
                onPressed: (_closing || _docStatusClosed(data))
                    ? null
                    : _closeRecruitment,
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '협업 완료 기록',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('협업 완료 기록은 준비 중입니다.')),
                  );
                },
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}
