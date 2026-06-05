part of 'main.dart';

/// 사업자 인증 신청·재신청: Storage 업로드 후 `users/{uid}` 업데이트.
class BusinessVerificationScreen extends StatefulWidget {
  const BusinessVerificationScreen({super.key});

  @override
  State<BusinessVerificationScreen> createState() =>
      _BusinessVerificationScreenState();
}

class _BusinessVerificationScreenState extends State<BusinessVerificationScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _bizNumberCtrl = TextEditingController();
  final TextEditingController _bizNameCtrl = TextEditingController();
  final TextEditingController _repNameCtrl = TextEditingController();
  final TextEditingController _bizPhoneCtrl = TextEditingController();
  final TextEditingController _bizAddressCtrl = TextEditingController();

  XFile? _pickedImageFile;
  bool _loadingHydrate = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromUserDoc());
  }

  @override
  void dispose() {
    _bizNumberCtrl.dispose();
    _bizNameCtrl.dispose();
    _repNameCtrl.dispose();
    _bizPhoneCtrl.dispose();
    _bizAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrateFromUserDoc() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingHydrate = false);
      return;
    }

    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    } on Object catch (_) {
      snap = null;
    }

    if (!mounted) return;

    final d = snap?.data();
    void setCtrlIfEmpty(TextEditingController c, String? text) {
      if (text == null || text.isEmpty) return;
      if (c.text.isEmpty) c.text = text;
    }

    if (d != null) {
      setCtrlIfEmpty(
        _bizNumberCtrl,
        _bizTrim(d['businessNumber']) ?? _bizTrim(d['bizRegNumber']),
      );
      setCtrlIfEmpty(_bizNameCtrl, _bizTrim(d['businessName']));
      setCtrlIfEmpty(
        _repNameCtrl,
        _bizTrim(d['representativeName']) ?? _bizTrim(d['ownerName']),
      );
      setCtrlIfEmpty(_bizPhoneCtrl, _bizTrim(d['businessPhone']));
      setCtrlIfEmpty(_bizAddressCtrl, _bizTrim(d['businessAddress']));
    }

    setState(() => _loadingHydrate = false);
  }

  String? _bizTrim(dynamic raw) {
    if (raw is! String) return null;
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
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

  /// 이미지 압축: 모바일은 FlutterImageCompress, 웹은 null 반환 (원본 바이트 사용).
  Future<dynamic> _compressLicenseJpeg(XFile xFile) async {
    return platformCompressImage(xFile, quality: 88, maxSide: 1600);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 92,
    );
    if (x == null || !mounted) return;
    setState(() => _pickedImageFile = x);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final bizNo = _bizNumberCtrl.text.trim();
    final bizName = _bizNameCtrl.text.trim();
    final rep = _repNameCtrl.text.trim();
    final phone = _bizPhoneCtrl.text.trim();
    final addr = _bizAddressCtrl.text.trim();

    if (bizNo.isEmpty ||
        bizName.isEmpty ||
        rep.isEmpty ||
        phone.isEmpty ||
        addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('필수 항목을 모두 입력해 주세요.')),
      );
      return;
    }

    if (_pickedImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사업자등록증 이미지를 선택해 주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // 모바일: 압축된 File, 웹: null (원본 바이트 사용)
      final compressedFile = await _compressLicenseJpeg(_pickedImageFile!);
      final uploadXFile = (compressedFile != null && !kIsWeb)
          ? XFile((compressedFile as dynamic).path as String)
          : _pickedImageFile!;

      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = 'business_licenses/${user.uid}/$ts.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      final bytes = await uploadXFile.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        <String, Object?>{
          'businessNumber': bizNo,
          'businessName': bizName,
          'representativeName': rep,
          'businessPhone': phone,
          'businessAddress': addr,
          'businessLicenseImageUrl': url,
          'businessVerificationStatus': 'pending',
          'businessVerificationSubmittedAt': FieldValue.serverTimestamp(),
          'businessVerificationUpdatedAt': FieldValue.serverTimestamp(),
          'businessVerificationRejectReason': '',
          if (user.email != null && user.email!.trim().isNotEmpty)
            'email': user.email!.trim(),
        },
        SetOptions(merge: true),
      );

      // 모바일에서만 임시 파일 삭제 (웹은 파일 시스템 없음)
      if (!kIsWeb && compressedFile != null) {
        try {
          platformDeleteFile((compressedFile as dynamic).path as String);
        } on Object catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사업자 인증을 제출했습니다. 심사 후 반영됩니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제출 실패: $e')),
        );
      }
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
          '사업자 인증',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: _loadingHydrate
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  8,
                  20,
                  poFullScreenScrollBottomPadding(context),
                ),
                children: [
                  Text(
                    '제출 정보는 심사용이며, 인증 전에는 다른 사용자에게 공개되지 않습니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _bizNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _decoration('사업자등록번호', '하이픈 없이 또는 000-00-00000'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bizNameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('상호명', '등록 상호'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _repNameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration('대표자명', ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bizPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration('사업장 전화번호', ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bizAddressCtrl,
                    textInputAction: TextInputAction.newline,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _decoration('사업장 주소', ''),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '사업자등록증',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _pickedImageFile == null
                          ? '이미지 선택'
                          : '이미지 변경됨 – 다시 선택',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_pickedImageFile != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: kIsWeb
                            ? Image.network(
                                _pickedImageFile!.path,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, e, s) =>
                                    const Center(child: Icon(Icons.image_outlined)),
                              )
                            : Image.file(
                                platformBuildFile(_pickedImageFile!.path),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('제출하기'),
                  ),
                ],
              ),
            ),
    );
  }
}
