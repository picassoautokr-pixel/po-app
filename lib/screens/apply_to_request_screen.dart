part of '../main.dart';

/// 파트너: 협업 공고 지원서 작성·수정.
class ApplyToRequestScreen extends StatefulWidget {
  const ApplyToRequestScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ApplyToRequestScreen> createState() => _ApplyToRequestScreenState();
}

class _ApplyToRequestScreenState extends State<ApplyToRequestScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _scheduleCtrl = TextEditingController();
  final TextEditingController _materialCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();

  bool _phoneVisible = true;
  bool _loading = true;
  bool _submitting = false;
  String? _initError;
  Map<String, dynamic>? _requestData;
  bool _hasExistingApplication = false;
  bool _blockAccepted = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _scheduleCtrl.dispose();
    _materialCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _initError = '로그인이 필요합니다.';
      });
      return;
    }

    try {
      final reqRef = FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim());
      final reqSnap = await reqRef.get();
      final reqData = reqSnap.data();
      if (!reqSnap.exists || reqData == null) {
        setState(() {
          _loading = false;
          _initError = '공고를 찾을 수 없습니다.';
        });
        return;
      }

      final ownerUid = _collaborationRequestString(reqData['ownerUid']);
      if (ownerUid.isNotEmpty && ownerUid == user.uid) {
        setState(() {
          _loading = false;
          _initError = '본인이 등록한 공고에는 지원할 수 없습니다.';
        });
        return;
      }

      final appSnap =
          await reqRef.collection('applications').doc(user.uid).get();
      final appData = appSnap.data();

      if (appSnap.exists && appData != null) {
        final p = appData['proposedPrice'];
        if (p is num) {
          _priceCtrl.text =
              p % 1 == 0 ? '${p.toInt()}' : p.toString();
        } else {
          final s = collaborationFormatProposedPrice(p);
          _priceCtrl.text = s == '미등록' ? '' : s;
        }
        _scheduleCtrl.text =
            _collaborationRequestString(appData['availableSchedule']);
        _materialCtrl.text =
            _collaborationRequestString(appData['materialOffer']);
        _messageCtrl.text = _collaborationRequestString(appData['message']);
        final vis = appData['isPhoneVisible'];
        _phoneVisible = vis is! bool || vis;
      }

      final st =
          _collaborationRequestString(appData?['status']).toLowerCase();
      final accepted = appSnap.exists && st == 'accepted';

      setState(() {
        _loading = false;
        _requestData = reqData;
        _hasExistingApplication = appSnap.exists;
        _blockAccepted = accepted;
      });
    } on Object catch (e) {
      setState(() {
        _loading = false;
        _initError = '불러오기 실패: $e';
      });
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<void> _submit() async {
    if (_blockAccepted || _submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final price = collaborationParseProposedPrice(_priceCtrl.text);
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제안 금액(숫자)을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final appRef = FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .collection('applications')
          .doc(user.uid);

      final existingSnap = await appRef.get();
      final curStatus =
          _collaborationRequestString(existingSnap.data()?['status'])
              .toLowerCase();
      if (existingSnap.exists && curStatus == 'accepted') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채택된 지원은 수정할 수 없습니다.')),
        );
        setState(() => _submitting = false);
        return;
      }

      final profileSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final prof = profileSnap.data();

      final applicantDisplayName = poHomeUserCardTitle(prof ?? {});
      final applicantPhone = poUserPrimaryPhone(prof ?? {});
      final applicantPrimaryCategory =
          _matchingFieldStr(prof?['primaryCategory']);
      final applicantSearchCategories =
          collaborationUserSearchCategoriesList(prof);

      final payload = <String, Object?>{
        'applicationId': user.uid,
        'requestId': widget.requestId.trim(),
        'applicantUid': user.uid,
        'applicantEmail': user.email ?? '',
        'applicantDisplayName': applicantDisplayName,
        'applicantPhone': applicantPhone,
        'applicantPrimaryCategory': applicantPrimaryCategory,
        'applicantSearchCategories': applicantSearchCategories,
        'proposedPrice': price,
        'availableSchedule': _scheduleCtrl.text.trim(),
        'materialOffer': _materialCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'isPhoneVisible': _phoneVisible,
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existingSnap.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await appRef.set(payload, SetOptions(merge: true));

      if (!existingSnap.exists) {
        final ownerUid =
            _collaborationRequestString(_requestData?['ownerUid']).trim();
        if (ownerUid.isNotEmpty && ownerUid != user.uid) {
          unawaited(createNotification(
            userId: ownerUid,
            type: 'application',
            title: '새 협업 지원이 도착했습니다',
            body: '$applicantDisplayName님이 협업을 지원했습니다',
            targetId: widget.requestId.trim(),
            targetType: 'request',
          ));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('협업 지원이 제출되었습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제출 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
          '협업 지원하기',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _initError!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                )
              : SafeArea(
                  top: false,
                  child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    poFullScreenScrollBottomPadding(context),
                  ),
                  children: [
                    if (_blockAccepted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.green.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '채택된 지원입니다. 내용을 수정할 수 없습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    DecoratedBox(
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
                              '공고 정보',
                              style: textTheme.labelSmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '공고 제목',
                              body: _requestData == null
                                  ? '미등록'
                                  : _collaborationDisplayTitle(_requestData!),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '작업 지역',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'location',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '일정',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'date',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '자재 조건',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'materialCondition',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '희망 금액',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'price',),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '지원 내용',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: _fieldDecoration('예: 300000'),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _scheduleCtrl,
                      decoration:
                          _fieldDecoration('예: 오늘 오후 3시 가능'),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _materialCtrl,
                      keyboardType: TextInputType.multiline,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _fieldDecoration(
                        '예: PPF 필름 지참 가능 / 랩핑 필름은 의뢰자 제공 필요',
                      ),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _messageCtrl,
                      keyboardType: TextInputType.multiline,
                      minLines: 5,
                      maxLines: 10,
                      decoration: _fieldDecoration(
                        '협업 가능 조건을 간단히 입력하세요',
                      ),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '전화 공개 여부',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Switch(
                          value: _phoneVisible,
                          onChanged: _blockAccepted
                              ? null
                              : (bool v) => setState(() => _phoneVisible = v),
                          activeTrackColor: _accent.withValues(alpha: 0.35),
                          activeThumbColor: _accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed:
                          (_blockAccepted || _submitting) ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_submitting
                          ? '저장 중…'
                          : (_hasExistingApplication
                              ? '지원 수정'
                              : '지원 제출')),
                    ),
                  ],
                ),
                ),
    );
  }
}
