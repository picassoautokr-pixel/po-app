part of '../main.dart';

/// 마감 디테일 등록 — Storage `finish_details/{uid}/{timestamp}.jpg` 후
/// `users/{uid}/finishDetails/{docId}` 저장.
class FinishDetailCreateScreen extends StatefulWidget {
  const FinishDetailCreateScreen({super.key});

  @override
  State<FinishDetailCreateScreen> createState() =>
      _FinishDetailCreateScreenState();
}

class _FinishDetailCreateScreenState extends State<FinishDetailCreateScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  String? _imagePath;  // 모바일에서는 파일 경로, 웹에서는 blob URL
  XFile? _pickedXFile;  // 웹/모바일 공통 XFile
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({required String label, required String hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade800,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    setState(() {
      _pickedXFile = x;
      _imagePath = x.path;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final category = _categoryController.text.trim();
    if (title.isEmpty ||
        description.isEmpty ||
        category.isEmpty ||
        _imagePath == null ||
        _imagePath!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목·설명·카테고리·이미지를 모두 입력해 주세요.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref(
        'finish_details/${user.uid}/$timestamp.jpg',
      );
      // 웹/모바일 공통: putData(바이트) 사용
      final uploadXFile = _pickedXFile ?? XFile(_imagePath!);
      final bytes = await uploadXFile.readAsBytes();
      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await storageRef.getDownloadURL();
      // ignore: avoid_print
      debugPrint(
        '[FinishDetailCreate] Storage upload OK path=finish_details/${user.uid}/'
        '$timestamp.jpg imageUrl=$imageUrl',
      );

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finishDetails')
          .doc();

      await docRef.set(<String, Object?>{
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // ignore: avoid_print
      debugPrint(
        '[FinishDetailCreate] Firestore write OK users/${user.uid}/finishDetails/'
        '${docRef.id} (title="$title")',
      );

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('마감 디테일이 등록되었습니다.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('등록에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
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
          '마감 디테일 등록',
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
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                math.max(
                  120,
                  poFullScreenScrollBottomPadding(context),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '이미지는 Firebase Storage에 저장되며, 완료 후 업체 프로필에 표시됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: '제목',
                      hint: '예: 도어 라인 PPF 마감 기준',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _categoryController,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: '카테고리',
                      hint: '예: PPF · 외장',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    minLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: _decoration(
                      label: '설명',
                      hint: '마감·이물·버블 기준 등',
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('갤러리에서 이미지 선택'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: kIsWeb
                            ? Image.network(
                                _imagePath!,
                                fit: BoxFit.cover,
                                errorBuilder: (ctx, e, s) =>
                                    const Center(child: Icon(Icons.image_outlined)),
                              )
                            : Image.file(
                                platformBuildFile(_imagePath!),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  ],
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('등록하기'),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ConstructionMainCategoryTile extends StatelessWidget {
  const _ConstructionMainCategoryTile({
    required this.mainTitle,
    required this.selectedKeys,
    required this.accent,
    required this.textTheme,
    required this.onToggle,
  });

  final String mainTitle;
  final Set<String> selectedKeys;
  final Color accent;
  final TextTheme textTheme;
  final void Function(String main, String sub, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final subs = ServiceCategoryCatalog.servicesForMain(mainTitle);
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 12, right: 12),
      collapsedIconColor: Colors.grey.shade600,
      iconColor: accent,
      shape: Border.all(color: Colors.transparent),
      collapsedShape: Border.all(color: Colors.transparent),
      title: Text(
        mainTitle,
        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      childrenPadding: EdgeInsets.zero,
      children: [
        for (final sub in subs)
          CheckboxListTile(
            value:
                selectedKeys.contains(ServiceCategoryCatalog.selectionKey(mainTitle, sub)),
            onChanged: (v) => onToggle(mainTitle, sub, v ?? false),
            title: Text(
              sub,
              style: textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            activeColor: accent,
          ),
      ],
    );
  }
}

class _DashedRoundRectPainter extends CustomPainter {
  const _DashedRoundRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  static const double _dashLength = 6;
  static const double _gapLength = 4;

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _CollaborationCard extends StatelessWidget {
  const _CollaborationCard({
    required this.title,
    required this.region,
    required this.when,
    required this.deadlineLine,
    this.accentLine = '',
    this.titleStatusChip,
    this.showUrgentBadge = false,
    this.description = '',
    required this.onTap,
  });

  final String title;
  final String region;
  final String when;
  final String deadlineLine;
  /// 상태가 마감 등일 때 강조 보조 줄(홈).
  final String accentLine;
  /// 모집중/마감/완료 칩(요청 탭 등).
  final String? titleStatusChip;
  final bool showUrgentBadge;
  final String description;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  title,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.35,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (showUrgentBadge)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      '긴급',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: Colors.red.shade800,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (titleStatusChip != null &&
                                    titleStatusChip!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color:
                                              _accent.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      titleStatusChip!,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: _accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey.shade400,
                            size: 22,
                          ),
                        ],
                      ),
                      if (accentLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          accentLine,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _accent,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            region,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              when,
                              style: textTheme.labelSmall?.copyWith(
                                color: _accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.event_available_outlined,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '모집 마감 · $deadlineLine',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderSide,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final BorderSide? borderSide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: LoginScreen._btnHeight,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
              border: borderSide != null
                  ? Border.fromBorderSide(borderSide!)
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

