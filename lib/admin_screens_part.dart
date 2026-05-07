part of 'main.dart';

/// 관리자 전용 본문: [child]는 `role == admin`일 때만 표시됩니다.
Widget _adminGateBody({required Widget child}) {
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) {
    return const Center(child: Text('로그인이 필요합니다.'));
  }
  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream:
        FirebaseFirestore.instance.collection('users').doc(me).snapshots(),
    builder: (context, snap) {
      if (snap.connectionState == ConnectionState.waiting &&
          !snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final d = snap.data?.data();
      if (!poIsAdminUser(d)) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '관리자만 이용할 수 있습니다.\n'
              '(Firestore에서 users/{uid}.role을 "admin"으로 설정하세요.)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
      return child;
    },
  );
}

/// Firestore 규칙에서는 `role == 'admin'`인 경우에만
/// 다른 사용자의 `businessVerification*` 필드 갱신을 허용하도록 제한해야 합니다.
/// 클라의 [poIsAdminUser] 노출 숨김만으로는 보안상 충분하지 않습니다.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

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
          '관리자',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            poFullScreenScrollBottomPadding(context),
          ),
          children: [
            Text(
              '관리 기능',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.12),
                child: Icon(Icons.verified_outlined, color: _accent),
              ),
              title: const Text('사업자 인증 관리'),
              subtitle: Text(
                '심사 대기 중인 업체 신청 검토',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(poSmoothPushRoute<void>(
                    const BusinessVerificationAdminScreen(),
                  )),
            ),
            Divider(height: 32, color: Colors.grey.shade200),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.12),
                child: Icon(Icons.upload_file_outlined, color: _accent),
              ),
              title: const Text('업체 대량 업로드'),
              subtitle: Text(
                'CSV 파일로 업체 일괄 등록',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                poSmoothPushRoute<void>(
                  const BusinessBulkUploadScreen(),
                ),
              ),
            ),
            Divider(height: 32, color: Colors.grey.shade200),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.12),
                child: Icon(Icons.store_mall_directory_outlined,
                    color: _accent),
              ),
              title: const Text('업체 인증 요청 관리'),
              subtitle: Text(
                '선등록 업체 Claim 신청 심사',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                poSmoothPushRoute<void>(
                  const BusinessClaimAdminScreen(),
                ),
              ),
            ),
            Divider(height: 32, color: Colors.grey.shade200),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _accent.withValues(alpha: 0.12),
                child: Icon(Icons.store_outlined, color: _accent),
              ),
              title: const Text('업체 데이터 관리'),
              subtitle: Text(
                '선등록 업체 목록 조회 및 등록',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                poSmoothPushRoute<void>(
                  const BusinessListAdminScreen(),
                ),
              ),
            ),
            Divider(height: 32, color: Colors.grey.shade200),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.flag_outlined, color: Colors.grey.shade700),
              ),
              title: Text(
                '신고 관리',
                style: TextStyle(color: Colors.grey.shade500),
              ),
              subtitle: Text(
                '추후 제공 예정',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessVerificationAdminScreen extends StatelessWidget {
  const BusinessVerificationAdminScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

  String _submitted(dynamic v) {
    final dt = _firestoreAsDateTime(v);
    if (dt == null) return '-';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
          '사업자 인증 · 대기 목록',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('businessVerificationStatus', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            poReportFirestoreSnapshotError(
              'admin_business_verification_list',
              snapshot.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                '심사 대기 중인 신청이 없습니다.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              poFullScreenScrollBottomPadding(context),
            ),
            itemCount: docs.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final d = doc.data();
              final img = _finishDetailFieldStr(d['businessLicenseImageUrl']);

              return Material(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(ctx).push(poSmoothPushRoute<void>(
                        BusinessVerificationReviewScreen(
                          targetUid: doc.id,
                        ),
                      )),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 88,
                            height: 64,
                            child: img.isEmpty
                                ? ColoredBox(
                                    color: Colors.grey.shade200,
                                    child: Icon(
                                      Icons.article_outlined,
                                      color: Colors.grey.shade500,
                                    ),
                                  )
                                : Image.network(
                                    img,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            ColoredBox(
                                      color: Colors.grey.shade200,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _matchingFieldStr(d['businessName'])
                                        .isEmpty
                                    ? '(상호 미등록)'
                                    : _matchingFieldStr(d['businessName']),
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              _adminMiniLine(textTheme,
                                  '대표', _matchingFieldStr(d['representativeName'])),
                              _adminMiniLine(textTheme,
                                  '등록번호', _matchingFieldStr(d['businessNumber'])),
                              _adminMiniLine(textTheme,
                                  '주소', _matchingFieldStr(d['businessAddress'])),
                              _adminMiniLine(textTheme,
                                  '전화', _matchingFieldStr(d['businessPhone'])),
                              Text(
                                '제출 ${_submitted(d['businessVerificationSubmittedAt'])}',
                                style: textTheme.labelSmall?.copyWith(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.grey.shade500),
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

  Widget _adminMiniLine(TextTheme textTheme, String k, String v) {
    final show = v.isEmpty ? '-' : v;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$k · $show',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(
          color: Colors.grey.shade800,
          height: 1.3,
        ),
      ),
    );
  }
}

class BusinessVerificationReviewScreen extends StatefulWidget {
  const BusinessVerificationReviewScreen({super.key, required this.targetUid});

  final String targetUid;

  @override
  State<BusinessVerificationReviewScreen> createState() =>
      _BusinessVerificationReviewScreenState();
}

class _BusinessVerificationReviewScreenState
    extends State<BusinessVerificationReviewScreen> {
  static const Color _accent = Color(0xFF007AFF);
  bool _busy = false;

  String _applicantEmailLine(Map<String, dynamic> d) {
    for (final key in <String>[
      'email',
      'userEmail',
      'contactEmail',
      'googleEmail',
    ]) {
      final s = _matchingFieldStr(d[key]);
      if (s.isNotEmpty) return s;
    }
    return '-';
  }

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // TODO(po-firestore-rules): 본 갱신은 관리자만 가능하도록 Rules에서 제한하세요.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.targetUid.trim())
          .set(
        <String, Object?>{
          'businessVerificationStatus': 'verified',
          'businessVerifiedAt': FieldValue.serverTimestamp(),
          'businessVerificationUpdatedAt': FieldValue.serverTimestamp(),
          'verifiedBusiness': true,
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('승인 처리했습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('승인 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('반려 사유'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '파트너에게 전달할 사유를 입력하세요.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('반려'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true) return;
    if (reason.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('반려 사유를 입력해 주세요.')),
        );
      }
      return;
    }

    setState(() => _busy = true);
    try {
      // TODO(po-firestore-rules): 본 갱신은 관리자만 가능하도록 Rules에서 제한하세요.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.targetUid.trim())
          .set(
        <String, Object?>{
          'businessVerificationStatus': 'rejected',
          'businessVerificationRejectReason': reason,
          'businessVerificationUpdatedAt': FieldValue.serverTimestamp(),
          'verifiedBusiness': false,
        },
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반려 처리했습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('반려 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(TextTheme tt, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value.isEmpty ? '-' : value,
            style: tt.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = widget.targetUid.trim();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '사업자 인증 검토',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            poReportFirestoreSnapshotError(
              'admin_business_verification_review_user',
              snap.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!.data() ?? <String, dynamic>{};
          final img = _finishDetailFieldStr(d['businessLicenseImageUrl']);

          return Column(
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
                    if (img.isEmpty)
                      Container(
                        height: 160,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '등록증 이미지가 없습니다.',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Material(
                            color: Colors.black12,
                            child: InkWell(
                              onTap: () =>
                                  _showFinishDetailImagePreview(context, img),
                              child: Image.network(
                                img,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                  child: Text('이미지 로드 실패'),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _row(textTheme, '상호명',
                        _matchingFieldStr(d['businessName'])),
                    _row(textTheme, '대표자명',
                        _matchingFieldStr(d['representativeName'])),
                    _row(textTheme, '사업자등록번호',
                        _matchingFieldStr(d['businessNumber'])),
                    _row(textTheme, '사업장 전화번호',
                        _matchingFieldStr(d['businessPhone'])),
                    _row(textTheme, '사업장 주소',
                        _matchingFieldStr(d['businessAddress'])),
                    _row(textTheme, '신청자 이메일', _applicantEmailLine(d)),
                    _row(textTheme, '신청자 UID', uid),
                    _row(
                      textTheme,
                      '제출일',
                      _formatFinishDetailCreatedAt(
                        d['businessVerificationSubmittedAt'],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : _reject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('반려'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _approve,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('승인'),
                      ),
                    ),
                  ],
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
