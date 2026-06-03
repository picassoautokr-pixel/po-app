part of '../main.dart';

/// 전문 시공 협업 공고 등록 폼
class CollaborationRequestCreateScreen extends StatefulWidget {
  const CollaborationRequestCreateScreen({super.key});

  @override
  State<CollaborationRequestCreateScreen> createState() =>
      _CollaborationRequestCreateScreenState();
}

class _CollaborationRequestCreateScreenState
    extends State<CollaborationRequestCreateScreen> {
  static const Color _accent = Color(0xFF007AFF);

  static const List<String> _materialOptions = <String>[
    '전부 제공',
    '일부 제공',
    '업체 준비',
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _selectedMain;
  final Set<String> _selectedSubKeys = <String>{};
  DateTime? _scheduleDate;
  bool _isOnSite = false;
  String _materialCondition = _materialOptions.first;
  bool _isUrgent = false;
  bool _recruitmentAlwaysOpen = true;
  DateTime? _recruitmentDeadlineDate;

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
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

  Widget _sectionCard(TextTheme textTheme, String title, List<Widget> body) {
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
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 14),
            ...body,
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final initial = _scheduleDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(now.year - 1, 1, 1)) ? now : initial,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accent,
              onPrimary: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _scheduleDate = picked);
    }
  }

  Future<void> _pickRecruitmentDeadlineDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _recruitmentDeadlineDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(now.year + 5, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accent,
              onPrimary: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _recruitmentDeadlineDate = picked);
    }
  }

  void _selectMain(String main) {
    setState(() {
      _selectedMain = main;
      _selectedSubKeys.clear();
    });
  }

  void _toggleSub(String sub) {
    final main = _selectedMain;
    if (main == null) return;
    setState(() {
      final k = ServiceCategoryCatalog.selectionKey(main, sub);
      final nowSelect = !_selectedSubKeys.contains(k);
      final next = ServiceCategoryCatalog.toggledSelectionSet(
        current: _selectedSubKeys,
        main: main,
        sub: sub,
        selected: nowSelect,
      );
      _selectedSubKeys
        ..clear()
        ..addAll(next);
    });
  }

  void _onSubmit() => _submitCollaborationRequest();

  Future<void> _submitCollaborationRequest() async {
    FocusScope.of(context).unfocus();
    if (!context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final messenger = ScaffoldMessenger.of(context);
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty ||
        _selectedMain == null ||
        _selectedMain!.trim().isEmpty ||
        location.isEmpty ||
        description.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('작업 제목·메인 카테고리·지역·상세 내용은 필수입니다.'),
        ),
      );
      return;
    }

    if (!_recruitmentAlwaysOpen && _recruitmentDeadlineDate == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('마감일을 선택해 주세요.')),
      );
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    bool dialogOpen = false;
    Object? caught;

    final dateStr =
        _scheduleDate == null ? '' : _formatDate(_scheduleDate!);
    final subs = ServiceCategoryCatalog.distinctSubs(_selectedSubKeys)
        .toList(growable: false);
    final priceText = _priceController.text.trim();

    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.25),
        builder: (ctx) => Center(
          child: CircularProgressIndicator(
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
      );
      dialogOpen = true;

      final ref =
          FirebaseFirestore.instance.collection('collaborationRequests').doc();
      final requestId = ref.id;

      final locPack = PoRegionFields.fromRegionFull(location);

      final Map<String, Object?> deadlinePack;
      if (_recruitmentAlwaysOpen) {
        deadlinePack = <String, Object?>{
          'deadlineType': 'always',
          'deadline': null,
          'deadlineText': '수시모집중',
        };
      } else {
        final dd = _recruitmentDeadlineDate!;
        deadlinePack = <String, Object?>{
          'deadlineType': 'date',
          'deadline': Timestamp.fromDate(
            DateTime(dd.year, dd.month, dd.day),
          ),
          'deadlineText': _formatDate(dd),
        };
      }

      await ref.set(<String, Object?>{
        'requestId': requestId,
        'ownerUid': user.uid,
        'ownerEmail': user.email ?? '',
        'title': title,
        'mainCategory': _selectedMain!,
        'serviceCategories': subs,
        'location':
            locPack.regionFull.isNotEmpty ? locPack.regionFull : location,
        ...poRegionCollaborationFirestoreMap(locPack),
        'date': dateStr,
        'isOnSite': _isOnSite,
        'materialCondition': _materialCondition,
        'price': priceText,
        'isUrgent': _isUrgent,
        'description': description,
        'workType': title,
        'status': 'open',
        ...deadlinePack,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e, st) {
      caught = e;
      debugPrint('$e\n$st');
    } finally {
      if (dialogOpen && context.mounted) {
        navigator.pop();
      }
    }

    if (!context.mounted) return;

    if (caught != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('등록하지 못했습니다: $caught')),
      );
      return;
    }

    _MainShellTabHost.goHomeTab();
    navigator.pop();

    messenger.showSnackBar(
      const SnackBar(content: Text('협업 요청이 등록되었습니다.')),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subs = _selectedMain == null
        ? const <String>[]
        : ServiceCategoryCatalog.servicesForMain(_selectedMain!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 공고 작성',
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
                8,
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
                    '모집 조건을 구체적으로 적을수록 맞는 파트너와 연결되기 쉽습니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(textTheme, '기본 정보', [
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '작업 제목 *',
                        hint: '예: PPF + 랩핑 협업 구함',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '지역 *',
                        hint: '예: 서울 강남구',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '메인 카테고리 *',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final main in ServiceCategoryCatalog.mainTitles)
                          FilterChip(
                            label: Text(
                              main,
                              style: textTheme.labelMedium?.copyWith(
                                fontSize: 11.5,
                                height: 1.2,
                              ),
                            ),
                            selected: _selectedMain == main,
                            onSelected: (_) => _selectMain(main),
                            selectedColor: _accent.withValues(alpha: 0.2),
                            checkmarkColor: _accent,
                          ),
                      ],
                    ),
                    if (_selectedMain != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '세부 시공분야 (복수 선택)',
                        style: textTheme.labelMedium?.copyWith(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final sub in subs)
                            FilterChip(
                              label: Text(sub),
                              selected: _selectedSubKeys.contains(
                                ServiceCategoryCatalog.selectionKey(
                                  _selectedMain!,
                                  sub,
                                ),
                              ),
                              onSelected: (_) => _toggleSub(sub),
                              selectedColor: _accent.withValues(alpha: 0.2),
                              checkmarkColor: _accent,
                            ),
                        ],
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '일정 · 현장', [
                    OutlinedButton.icon(
                      onPressed: _pickScheduleDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 20),
                      label: Text(
                        _scheduleDate == null
                            ? '일정 선택 (DatePicker)'
                            : '일정: ${_formatDate(_scheduleDate!)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '출장 여부',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('방문 시공'),
                          icon: Icon(Icons.storefront_outlined, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('출장 시공'),
                          icon: Icon(Icons.local_shipping_outlined, size: 18),
                        ),
                      ],
                      selected: <bool>{_isOnSite},
                      onSelectionChanged: (set) {
                        setState(() => _isOnSite = set.first);
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? _accent
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '모집 마감', [
                    Text(
                      '마감 방식',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('마감일 지정'),
                          icon: Icon(Icons.calendar_month_outlined, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('수시모집중'),
                          icon: Icon(Icons.all_inclusive_rounded, size: 18),
                        ),
                      ],
                      selected: <bool>{_recruitmentAlwaysOpen},
                      onSelectionChanged: (Set<bool> sel) {
                        setState(() => _recruitmentAlwaysOpen = sel.first);
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? _accent
                              : Colors.black87,
                        ),
                      ),
                    ),
                    if (!_recruitmentAlwaysOpen) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _pickRecruitmentDeadlineDate,
                        icon: const Icon(Icons.event_rounded, size: 20),
                        label: Text(
                          _recruitmentDeadlineDate == null
                              ? '마감일 선택 (필수)'
                              : '모집 마감일: ${_formatDate(_recruitmentDeadlineDate!)}',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _accent,
                          side: BorderSide(
                              color: _accent.withValues(alpha: 0.45)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '조건 · 금액', [
                    Text(
                      '자재 조건',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '자재 제공 범위',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in _materialOptions)
                          ChoiceChip(
                            label: Text(o),
                            selected: _materialCondition == o,
                            onSelected: (_) =>
                                setState(() => _materialCondition = o),
                            selectedColor: _accent.withValues(alpha: 0.2),
                            labelStyle: textTheme.labelLarge?.copyWith(
                              color: _materialCondition == o
                                  ? _accent
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '희망 금액 (선택)',
                        hint: '숫자만 입력 (원 단위 등)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '긴급 모집',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '리스트에 긴급 배지로 표시됩니다.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      value: _isUrgent,
                      activeTrackColor: _accent.withValues(alpha: 0.45),
                      activeThumbColor: _accent,
                      onChanged: (v) => setState(() => _isUrgent = v),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '상세 내용', [
                    TextField(
                      controller: _descriptionController,
                      maxLines: 6,
                      minLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: _fieldDecoration(
                        label: '상세 내용 *',
                        hint:
                            '작업 범위, 차종, 필요 인력, 소통 방식 등 구체적으로 적어 주세요.',
                      ),
                    ),
                  ]),
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
                onPressed: _onSubmit,
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
                child: const Text('협업 요청 등록'),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// 사업자명 → 매장이름 → 대표자명 → 별명 순으로 앱에 표시할 이름을 고릅니다.
String computePoAppDisplayName({
  required String businessName,
  required String storeName,
  required String representativeName,
  required String nickname,
}) {
  String t(String v) => v.trim();
  if (t(businessName).isNotEmpty) return t(businessName);
  if (t(storeName).isNotEmpty) return t(storeName);
  if (t(representativeName).isNotEmpty) return t(representativeName);
  if (t(nickname).isNotEmpty) return t(nickname);
  return '이름을 입력해주세요';
}
