part of 'main.dart';

// ---------------------------------------------------------------------------
// 선등록 업체 Claim 시스템
// ---------------------------------------------------------------------------
//
// Firestore 컬렉션:
//   businesses/{businessId}        - 관리자가 미리 등록한 업체 데이터
//   businessClaims/{claimId}       - 사용자가 신청한 업체 Claim
//
// businesses 문서 주요 필드:
//   businessName, ownerName, businessNumber, phone, address, region,
//   category, subCategories, description, website,
//   status, verified, claimed, claimedByUid, createdByAdmin,
//   createdAt, updatedAt
//
// businessClaims 문서 주요 필드:
//   businessId, applicantUid, businessNumber, representativeName, phone,
//   businessLicenseImageUrl, businessCardImageUrl, description,
//   status (pending | approved | rejected), rejectReason, createdAt, reviewedAt
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 공통 헬퍼
// ---------------------------------------------------------------------------

String _claimFieldStr(dynamic v) => v is String ? v.trim() : '';

String _claimFormatDate(dynamic v) {
  final dt = _firestoreAsDateTime(v);
  if (dt == null) return '-';
  return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// 공통 위젯
// ---------------------------------------------------------------------------

class _BusinessBadge extends StatelessWidget {
  const _BusinessBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _BusinessInfoRow extends StatelessWidget {
  const _BusinessInfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: tt.labelSmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w700,
                  height: 1.5),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: tt.bodySmall?.copyWith(
                  color:
                      value.isEmpty ? Colors.grey.shade400 : Colors.black87,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _claimAdminLine(TextTheme tt, String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      '$k · ${v.isEmpty ? "-" : v}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: tt.bodySmall?.copyWith(color: Colors.grey.shade800, height: 1.3),
    ),
  );
}

Widget _claimDetailRow(TextTheme tt, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
              color: Colors.grey.shade600, fontWeight: FontWeight.w700),
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

// ---------------------------------------------------------------------------
// 업체 상세 화면
// ---------------------------------------------------------------------------

class BusinessDetailScreen extends StatelessWidget {
  const BusinessDetailScreen({super.key, required this.businessId});

  final String businessId;

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 정보',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            poReportFirestoreSnapshotError('business_detail', snap.error!);
            return Center(child: poFirestoreUserErrorPlaceholder(context));
          }
          final d = snap.data?.data();
          if (d == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '업체 정보를 찾을 수 없습니다.',
                  style: tt.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            );
          }

          final businessName = _claimFieldStr(d['businessName']);
          final ownerName = _claimFieldStr(d['ownerName']);
          final businessNumber = _claimFieldStr(d['businessNumber']);
          final phone = _claimFieldStr(d['phone']);
          final storePhone = _claimFieldStr(d['storePhone']);
          final mobilePhone = _claimFieldStr(d['mobilePhone']);
          final virtualPhone = _claimFieldStr(d['virtualPhone']);
          final phoneOpts = _extractBusinessPhoneOptions(d);
          final address = _claimFieldStr(d['address']);
          final region = _claimFieldStr(d['region']);
          final category = _claimFieldStr(d['category']);
          final description = _claimFieldStr(d['description']);
          final website = _claimFieldStr(d['website']);
          final claimed = d['claimed'] == true;
          final claimedByUid = _claimFieldStr(d['claimedByUid']);
          final createdByAdmin = d['createdByAdmin'] == true;
          final isMyBusiness = claimed && claimedByUid == myUid;
          final canClaim = !claimed && myUid != null && myUid.isNotEmpty;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              poFullScreenScrollBottomPadding(context) + 80,
            ),
            children: [
              // 상태 배지 행
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (claimed)
                    _BusinessBadge(label: '인증업체', color: _accent)
                  else if (createdByAdmin)
                    _BusinessBadge(
                        label: '사전 등록 업체', color: Colors.grey.shade600),
                  if (isMyBusiness)
                    _BusinessBadge(
                        label: '내 업체', color: Colors.green.shade700),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                businessName.isEmpty ? '업체명 미등록' : businessName,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),

              _BusinessInfoRow(label: '대표자', value: ownerName),
              _BusinessInfoRow(label: '사업자번호', value: businessNumber),
              if (storePhone.isNotEmpty)
                _BusinessInfoRow(label: '매장 전화', value: storePhone),
              if (mobilePhone.isNotEmpty)
                _BusinessInfoRow(label: '휴대폰', value: mobilePhone),
              if (virtualPhone.isNotEmpty)
                _BusinessInfoRow(label: '대표번호', value: virtualPhone),
              if (storePhone.isEmpty &&
                  mobilePhone.isEmpty &&
                  virtualPhone.isEmpty)
                _BusinessInfoRow(label: '전화번호', value: phone),
              _BusinessInfoRow(label: '주소', value: address),
              _BusinessInfoRow(label: '지역', value: region),
              _BusinessInfoRow(label: '분야', value: category),
              _BusinessInfoRow(label: '웹사이트', value: website),

              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '소개',
                  style: tt.labelSmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: tt.bodyMedium?.copyWith(height: 1.5)),
              ],

              const SizedBox(height: 28),

              if (phoneOpts.isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: () => poShowBusinessPhoneSheet(context, d),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text(
                    '업체 전화하기',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(
                        color: _accent.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (canClaim)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    poSmoothPushRoute<void>(
                      BusinessClaimScreen(
                        businessId: businessId,
                        businessName: businessName,
                        prefillBusinessNumber: businessNumber,
                        prefillOwnerName: ownerName,
                        prefillPhone: phone,
                      ),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text(
                    '내 업체 인증하기',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                )
              else if (!canClaim && myUid == null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.login_outlined,
                            color: Colors.grey.shade500, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '인증 신청은 로그인 후 가능합니다.',
                          style: tt.bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                )
              else if (claimed && !isMyBusiness)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            color: Colors.grey.shade500, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '이미 인증된 업체입니다.',
                          style: tt.bodySmall
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 업체 Claim 신청 화면
// ---------------------------------------------------------------------------

class BusinessClaimScreen extends StatefulWidget {
  const BusinessClaimScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    this.prefillBusinessNumber = '',
    this.prefillOwnerName = '',
    this.prefillPhone = '',
  });

  final String businessId;
  final String businessName;
  final String prefillBusinessNumber;
  final String prefillOwnerName;
  final String prefillPhone;

  @override
  State<BusinessClaimScreen> createState() => _BusinessClaimScreenState();
}

class _BusinessClaimScreenState extends State<BusinessClaimScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late final TextEditingController _bizNumberCtrl;
  late final TextEditingController _repNameCtrl;
  late final TextEditingController _phoneCtrl;
  final TextEditingController _descCtrl = TextEditingController();

  XFile? _licenseImageFile;
  XFile? _cardImageFile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bizNumberCtrl =
        TextEditingController(text: widget.prefillBusinessNumber);
    _repNameCtrl = TextEditingController(text: widget.prefillOwnerName);
    _phoneCtrl = TextEditingController(text: widget.prefillPhone);
  }

  @override
  void dispose() {
    _bizNumberCtrl.dispose();
    _repNameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isLicense}) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() {
      if (isLicense) {
        _licenseImageFile = file;
      } else {
        _cardImageFile = file;
      }
    });
  }

  Future<String> _uploadImage(XFile file, String storagePath) async {
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(
      File(file.path),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다.')));
      return;
    }

    final bizNumber = _bizNumberCtrl.text.trim();
    final repName = _repNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (bizNumber.isEmpty || repName.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('사업자등록번호·대표자명·휴대폰번호는 필수입니다.')));
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      String licenseUrl = '';
      String cardUrl = '';

      if (_licenseImageFile != null) {
        licenseUrl = await _uploadImage(
          _licenseImageFile!,
          'business_claims/${user.uid}/$ts/license.jpg',
        );
      }
      if (_cardImageFile != null) {
        cardUrl = await _uploadImage(
          _cardImageFile!,
          'business_claims/${user.uid}/$ts/card.jpg',
        );
      }

      final claimRef =
          FirebaseFirestore.instance.collection('businessClaims').doc();
      await claimRef.set(<String, Object?>{
        'businessId': widget.businessId,
        'applicantUid': user.uid,
        'businessNumber': bizNumber,
        'representativeName': repName,
        'phone': phone,
        'businessLicenseImageUrl': licenseUrl,
        'businessCardImageUrl': cardUrl,
        'description': _descCtrl.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint(
        '[BusinessClaim] submitted claimId=${claimRef.id} '
        'businessId=${widget.businessId} uid=${user.uid}',
      );

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
          content: Text(
              '인증 신청이 접수되었습니다. 심사 후 결과를 안내드립니다.')));
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('신청 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decor({required String label, String hint = ''}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w500,
          fontSize: 14),
      floatingLabelStyle:
          const TextStyle(color: _accent, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5)),
    );
  }

  Widget _imagePickerTile({
    required String label,
    required XFile? file,
    required VoidCallback onTap,
  }) {
    final tt = Theme.of(context).textTheme;
    final picked = file != null;
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: picked ? Colors.green.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: picked
                  ? Colors.green.shade300
                  : Colors.grey.shade300),
        ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                picked
                    ? Icons.check_circle_outline
                    : Icons.upload_file_outlined,
                color: picked
                    ? Colors.green.shade700
                    : Colors.grey.shade500,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  picked ? p.basename(file.path) : label,
                  style: tt.bodyMedium?.copyWith(
                      color: picked
                          ? Colors.green.shade800
                          : Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!picked)
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '내 업체 인증 신청',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  math.max(100, poFullScreenScrollBottomPadding(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 인증 대상 업체 안내
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF007AFF).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF007AFF)
                                .withValues(alpha: 0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '인증 신청 업체',
                              style: tt.labelSmall?.copyWith(
                                  color: const Color(0xFF007AFF),
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.businessName.isEmpty
                                  ? '(이름 없음)'
                                  : widget.businessName,
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '[신청 정보 입력]',
                      style: tt.labelMedium?.copyWith(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bizNumberCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: _decor(
                          label: '사업자등록번호 *', hint: '000-00-00000'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _repNameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: _decor(
                          label: '대표자명 *', hint: '사업자등록증 기준 대표자명'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: _decor(
                          label: '휴대폰번호 *', hint: '010-0000-0000'),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '[증빙 서류 업로드]',
                      style: tt.labelMedium?.copyWith(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    _imagePickerTile(
                      label: '사업자등록증 업로드',
                      file: _licenseImageFile,
                      onTap: () => _pickImage(isLicense: true),
                    ),
                    const SizedBox(height: 10),
                    _imagePickerTile(
                      label: '명함 사진 업로드',
                      file: _cardImageFile,
                      onTap: () => _pickImage(isLicense: false),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '[추가 설명 (선택)]',
                      style: tt.labelMedium?.copyWith(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: _decor(
                        label: '추가 설명',
                        hint:
                            '업체 소유 확인에 도움이 되는 내용을 자유롭게 입력하세요.',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '제출한 서류는 업체 소유 확인 목적으로만 사용됩니다.\n'
                      '심사에는 영업일 기준 1~3일이 소요될 수 있습니다.',
                      style: tt.bodySmall?.copyWith(
                          color: Colors.grey.shade500, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('인증 신청하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 관리자: 업체 Claim 요청 목록
// ---------------------------------------------------------------------------

class BusinessClaimAdminScreen extends StatelessWidget {
  const BusinessClaimAdminScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 인증 요청 관리',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('businessClaims')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              poReportFirestoreSnapshotError(
                  'admin_business_claims', snapshot.error!);
              return Center(
                  child: poFirestoreUserErrorPlaceholder(context));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  '대기 중인 업체 인증 요청이 없습니다.',
                  style:
                      tt.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, poFullScreenScrollBottomPadding(context)),
              itemCount: docs.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final d = doc.data();
                final licenseUrl =
                    _claimFieldStr(d['businessLicenseImageUrl']);
                final hasImage = _isValidImageUrl(licenseUrl);

                return Material(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(ctx).push(
                      poSmoothPushRoute<void>(
                        BusinessClaimReviewScreen(claimId: doc.id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 72,
                              height: 72,
                              child: hasImage
                                  ? Image.network(
                                      licenseUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stack) =>
                                          ColoredBox(
                                        color: Colors.grey.shade200,
                                        child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.grey.shade500),
                                      ),
                                    )
                                  : ColoredBox(
                                      color: Colors.grey.shade200,
                                      child: Icon(Icons.article_outlined,
                                          color: Colors.grey.shade500),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _claimAdminLine(tt, '업체 ID',
                                    _claimFieldStr(d['businessId'])),
                                _claimAdminLine(tt, '대표자',
                                    _claimFieldStr(d['representativeName'])),
                                _claimAdminLine(tt, '등록번호',
                                    _claimFieldStr(d['businessNumber'])),
                                Text(
                                  '신청 ${_claimFormatDate(d['createdAt'])}',
                                  style: tt.labelSmall?.copyWith(
                                      color: _accent,
                                      fontWeight: FontWeight.w700),
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
}

// ---------------------------------------------------------------------------
// 관리자: Claim 상세 심사 화면
// ---------------------------------------------------------------------------

class BusinessClaimReviewScreen extends StatefulWidget {
  const BusinessClaimReviewScreen({super.key, required this.claimId});
  final String claimId;

  @override
  State<BusinessClaimReviewScreen> createState() =>
      _BusinessClaimReviewScreenState();
}

class _BusinessClaimReviewScreenState
    extends State<BusinessClaimReviewScreen> {
  static const Color _accent = Color(0xFF007AFF);
  bool _busy = false;

  Future<void> _approve(Map<String, dynamic> claimData) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('업체 인증 승인'),
        content: const Text(
            '이 신청을 승인하면 업체에 인증 표시가 추가됩니다.\n계속하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('승인')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final businessId = _claimFieldStr(claimData['businessId']);
      final applicantUid = _claimFieldStr(claimData['applicantUid']);
      final businessNumber = _claimFieldStr(claimData['businessNumber']);
      final repName = _claimFieldStr(claimData['representativeName']);

      // 1. businesses 컬렉션 업데이트
      if (businessId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('businesses')
            .doc(businessId)
            .set(<String, Object?>{
          'claimed': true,
          'claimedByUid': applicantUid,
          'verified': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 2. users 컬렉션 업데이트
      if (applicantUid.isNotEmpty) {
        String businessName = '';
        if (businessId.isNotEmpty) {
          final bizSnap = await FirebaseFirestore.instance
              .collection('businesses')
              .doc(businessId)
              .get();
          businessName = _claimFieldStr(bizSnap.data()?['businessName']);
        }

        final userUpdate = <String, Object?>{
          'linkedBusinessId': businessId,
          'linkedBusinessName': businessName,
          'businessVerificationStatus': 'verified',
          'businessVerifiedAt': FieldValue.serverTimestamp(),
          'verifiedBusiness': true,
        };
        if (businessNumber.isNotEmpty) {
          userUpdate['businessNumber'] = businessNumber;
        }
        if (repName.isNotEmpty) {
          userUpdate['representativeName'] = repName;
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(applicantUid)
            .set(userUpdate, SetOptions(merge: true));
      }

      // 3. claim 상태 approved로 변경
      await FirebaseFirestore.instance
          .collection('businessClaims')
          .doc(widget.claimId)
          .set(<String, Object?>{
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint(
        '[BusinessClaimReview] approved claimId=${widget.claimId} '
        'businessId=$businessId applicantUid=$applicantUid',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('승인 처리했습니다.')));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('승인 실패: $e')));
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
            hintText: '신청자에게 전달할 반려 사유를 입력하세요.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
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
            const SnackBar(content: Text('반려 사유를 입력해 주세요.')));
      }
      return;
    }

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('businessClaims')
          .doc(widget.claimId)
          .set(<String, Object?>{
        'status': 'rejected',
        'rejectReason': reason,
        'reviewedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('반려 처리했습니다.')));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('반려 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 인증 요청 심사',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('businessClaims')
              .doc(widget.claimId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              poReportFirestoreSnapshotError(
                  'admin_claim_review', snap.error!);
              return Center(
                  child: poFirestoreUserErrorPlaceholder(context));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data?.data() ?? <String, dynamic>{};
            final licenseUrl =
                _claimFieldStr(d['businessLicenseImageUrl']);
            final cardUrl = _claimFieldStr(d['businessCardImageUrl']);
            final status = _claimFieldStr(d['status']);
            final isPending = status == 'pending' || status.isEmpty;

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        20, 8, 20, poFullScreenScrollBottomPadding(context)),
                    children: [
                      // 처리 상태 배너
                      if (!isPending) ...[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: status == 'approved'
                                ? Colors.green.shade50
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: status == 'approved'
                                  ? Colors.green.shade200
                                  : Colors.red.shade200,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              status == 'approved'
                                  ? '이미 승인된 신청입니다.'
                                  : '이미 반려된 신청입니다.',
                              style: tt.bodySmall?.copyWith(
                                color: status == 'approved'
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      _claimDetailRow(tt, '업체 ID',
                          _claimFieldStr(d['businessId'])),
                      _claimDetailRow(tt, '신청자 UID',
                          _claimFieldStr(d['applicantUid'])),
                      _claimDetailRow(tt, '사업자등록번호',
                          _claimFieldStr(d['businessNumber'])),
                      _claimDetailRow(tt, '대표자명',
                          _claimFieldStr(d['representativeName'])),
                      _claimDetailRow(
                          tt, '휴대폰번호', _claimFieldStr(d['phone'])),
                      _claimDetailRow(tt, '추가 설명',
                          _claimFieldStr(d['description'])),
                      _claimDetailRow(
                          tt, '신청일', _claimFormatDate(d['createdAt'])),
                      if (_claimFieldStr(d['rejectReason']).isNotEmpty)
                        _claimDetailRow(tt, '반려 사유',
                            _claimFieldStr(d['rejectReason'])),
                      const SizedBox(height: 8),

                      // 사업자등록증 이미지
                      if (_isValidImageUrl(licenseUrl)) ...[
                        Text(
                          '사업자등록증',
                          style: tt.labelSmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Material(
                              color: Colors.black12,
                              child: InkWell(
                                onTap: () =>
                                    _showFinishDetailImagePreview(
                                        context, licenseUrl),
                                child: Image.network(
                                  licenseUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      const Center(
                                          child: Text('이미지 로드 실패')),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 명함 이미지
                      if (_isValidImageUrl(cardUrl)) ...[
                        Text(
                          '명함',
                          style: tt.labelSmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Material(
                              color: Colors.black12,
                              child: InkWell(
                                onTap: () =>
                                    _showFinishDetailImagePreview(
                                        context, cardUrl),
                                child: Image.network(
                                  cardUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stack) =>
                                      const Center(
                                          child: Text('이미지 로드 실패')),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),

                // 승인/반려 버튼 (pending 상태일 때만)
                if (isPending)
                  SafeArea(
                    minimum:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _reject,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(
                                  color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                            child: const Text('반려'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                _busy ? null : () => _approve(d),
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
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

// ---------------------------------------------------------------------------
// 관리자: 업체 직접 등록 화면
// ---------------------------------------------------------------------------
// TODO(csv-import): 향후 CSV Import Tool 연결 예정
//   - businesses 컬렉션에 CSV/엑셀 데이터를 일괄 업로드하는 도구 연결 예정
//   - 필드 매핑: businessName, ownerName, businessNumber, phone,
//               address, region, category, description, website

class BusinessRegisterAdminScreen extends StatefulWidget {
  const BusinessRegisterAdminScreen({super.key});

  @override
  State<BusinessRegisterAdminScreen> createState() =>
      _BusinessRegisterAdminScreenState();
}

class _BusinessRegisterAdminScreenState
    extends State<BusinessRegisterAdminScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final _bizNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _bizNumberCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _bizNumberCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _regionCtrl.dispose();
    _categoryCtrl.dispose();
    _descCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decor({required String label, String hint = ''}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w500,
          fontSize: 14),
      floatingLabelStyle:
          const TextStyle(color: _accent, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5)),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final name = _bizNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업체명은 필수입니다.')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final docRef =
          FirebaseFirestore.instance.collection('businesses').doc();
      await docRef.set(<String, Object?>{
        'businessName': name,
        'ownerName': _ownerNameCtrl.text.trim(),
        'businessNumber': _bizNumberCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'region': _regionCtrl.text.trim(),
        'category': _categoryCtrl.text.trim(),
        'subCategories': <String>[],
        'description': _descCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'status': 'active',
        'verified': false,
        'claimed': false,
        'claimedByUid': null,
        'createdByAdmin': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint(
          '[BusinessRegisterAdmin] created businessId=${docRef.id} name=$name');
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text('업체 "$name"이(가) 등록되었습니다.')));
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('등록 실패: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 직접 등록',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _adminGateBody(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    math.max(100, poFullScreenScrollBottomPadding(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '관리자 전용 · 업체를 직접 등록합니다.\n'
                            'TODO(csv-import): 향후 CSV Import Tool 연결 예정',
                            style: tt.bodySmall?.copyWith(
                                color: Colors.amber.shade900, height: 1.45),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                          controller: _bizNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decor(label: '업체명 *', hint: '상호 또는 브랜드명')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _ownerNameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decor(label: '대표자명', hint: '대표 이름')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _bizNumberCtrl,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: _decor(
                              label: '사업자등록번호', hint: '000-00-00000')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: _decor(label: '대표 전화번호')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _addressCtrl,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decor(label: '주소', hint: '도로명 주소')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _regionCtrl,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decor(label: '지역', hint: '서울 강남구 등')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _categoryCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _decor(
                              label: '분야', hint: '자동차 / 도장 / 랩핑 등')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _websiteCtrl,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decor(label: '웹사이트', hint: 'https://')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _descCtrl,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: _decor(
                              label: '소개', hint: '업체 소개를 입력하세요.')),
                    ],
                  ),
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('업체 등록'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 관리자: 업체 목록 화면
// ---------------------------------------------------------------------------

class BusinessListAdminScreen extends StatelessWidget {
  const BusinessListAdminScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 목록',
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined),
            tooltip: '업체 등록',
            onPressed: () => Navigator.of(context).push(
              poSmoothPushRoute<void>(
                  const BusinessRegisterAdminScreen()),
            ),
          ),
        ],
      ),
      body: _adminGateBody(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('businesses')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              poReportFirestoreSnapshotError(
                  'admin_business_list', snapshot.error!);
              return Center(
                  child: poFirestoreUserErrorPlaceholder(context));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      '등록된 업체가 없습니다.',
                      style: tt.bodyMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        poSmoothPushRoute<void>(
                            const BusinessRegisterAdminScreen()),
                      ),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('업체 등록'),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, poFullScreenScrollBottomPadding(context)),
              itemCount: docs.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final d = docs[i].data();
                final claimed = d['claimed'] == true;
                final name = _claimFieldStr(d['businessName']);
                final region = _claimFieldStr(d['region']);
                final category = _claimFieldStr(d['category']);

                return Material(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(ctx).push(
                      poSmoothPushRoute<void>(
                        BusinessDetailScreen(businessId: docs[i].id),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty ? '(이름 없음)' : name,
                                  style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [region, category]
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                                  style: tt.bodySmall?.copyWith(
                                      color: Colors.grey.shade600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _BusinessBadge(
                            label: claimed ? '인증' : '미인증',
                            color: claimed
                                ? _accent
                                : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              color: Colors.grey.shade400, size: 18),
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
}
