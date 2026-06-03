part of '../main.dart';

/// 업체 · 프로필 정보 관리
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late final TextEditingController _loginEmailController;
  late final TextEditingController _googleNameController;
  late final TextEditingController _bizRegNumberController;
  late final TextEditingController _businessNameController;
  late final TextEditingController _repNameController;
  late final TextEditingController _businessPhoneController;
  late final TextEditingController _storeNameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _appDisplayNameController;

  /// 선택된 서비스 라인: `메인\u001f서브`(내부 키, Firestore에는 펼쳐서 저장).
  var _selectedServiceKeys = <String>{};

  /// 서브 라벨 기준 선택(체크) 순서 — searchCategories · categoryPriority · primary 에 사용.
  var _orderedSubLabels = <String>[];

  /// 협업 매칭용(별도 폼 미노출 — 기본값으로 유지 가능).
  var _matchingIsAvailable = true;
  final List<String> _matchingRegions = [];
  String _matchingPriceRange = '';
  String _matchingResponseSpeed = '';

  String _businessVerificationStatusNormalized = 'unverified';
  String _businessVerificationRejectReason = '';

  void _onProfileFieldChanged() {
    _appDisplayNameController.text = computePoAppDisplayName(
      businessName: _businessNameController.text,
      storeName: _storeNameController.text,
      representativeName: _repNameController.text,
      nickname: _nicknameController.text,
    );
  }

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

  InputDecoration _readonlyFieldDecoration({
    required String label,
    required String hint,
  }) {
    return _fieldDecoration(label: label, hint: hint).copyWith(
      fillColor: Colors.grey.shade50,
    );
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _loginEmailController = TextEditingController(text: user?.email ?? '-');
    _googleNameController =
        TextEditingController(text: user?.displayName ?? '-');
    _bizRegNumberController = TextEditingController();
    _businessNameController = TextEditingController();
    _repNameController = TextEditingController();
    _businessPhoneController = TextEditingController();
    _storeNameController = TextEditingController();
    _nicknameController = TextEditingController();
    _appDisplayNameController = TextEditingController();
    _onProfileFieldChanged();
    _businessNameController.addListener(_onProfileFieldChanged);
    _storeNameController.addListener(_onProfileFieldChanged);
    _repNameController.addListener(_onProfileFieldChanged);
    _nicknameController.addListener(_onProfileFieldChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFirestoreProfile();
    });
  }

  /// Firestore 문서 문자열 필드 로드 후 컨트롤러 및 시공 분야 선택 반영.
  Future<void> _loadFirestoreProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
    } catch (_) {
      snap = null;
    }

    if (!mounted) return;
    final data = snap?.data();
    if (data == null) return;
    _applyFirestoreProfile(data);
  }

  String? _firestoreTrimmedText(dynamic raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  void _hydrateEditableField(TextEditingController c, Map<String, dynamic> d,
      List<String> fieldKeys) {
    for (final key in fieldKeys) {
      final text = _firestoreTrimmedText(d[key]);
      if (text != null) {
        if (c.text != text) c.text = text;
        break;
      }
    }
  }

  /// `users/{uid}` 문서를 현재 폼에 합류(충돌 시 Firestore 우선 적용 후 표시 이름 재계산).
  void _applyFirestoreProfile(Map<String, dynamic> doc) {
    _hydrateEditableField(_bizRegNumberController, doc,
        const ['bizRegNumber', 'businessNumber']);
    _hydrateEditableField(_businessNameController, doc,
        const ['businessName']);
    _hydrateEditableField(
      _repNameController,
      doc,
      const ['representativeName', 'repName'],
    );
    _hydrateEditableField(_businessPhoneController, doc,
        const ['businessPhone']);
    _hydrateEditableField(_storeNameController, doc, const ['storeName']);
    _hydrateEditableField(_nicknameController, doc, const ['nickname']);

    final nextKeys = ServiceCategoryCatalog.selectionKeysFromFirestore(
      serviceCategories: doc['serviceCategories'],
    );

    setState(() {
      _selectedServiceKeys = nextKeys;
      final subs = ServiceCategoryCatalog.distinctSubs(nextKeys);
      _orderedSubLabels = _restoreSubOrderFromDoc(doc, subs);
      _hydrateMatchingFields(doc);
      _businessVerificationStatusNormalized =
          poBusinessVerificationUiState(doc);
      _businessVerificationRejectReason = _matchingFieldStr(
        doc['businessVerificationRejectReason'],
      );
    });
    _onProfileFieldChanged();
  }

  List<String> _restoreSubOrderFromDoc(
      Map<String, dynamic> doc, Set<String> validSubs,) {
    if (validSubs.isEmpty) return [];
    final fromPriority = _subOrderFromCategoryPriority(
      doc['categoryPriority'],
      validSubs,
    );
    if (fromPriority.isNotEmpty) {
      final rest =
          validSubs.where((s) => !fromPriority.contains(s)).toList()..sort();
      return [...fromPriority, ...rest];
    }
    final fromSearch =
        _subOrderFromSearchCategories(doc['searchCategories'], validSubs);
    if (fromSearch.isNotEmpty) {
      final rest =
          validSubs.where((s) => !fromSearch.contains(s)).toList()..sort();
      return [...fromSearch, ...rest];
    }
    final alpha = validSubs.toList()..sort();
    return alpha;
  }

  /// `categoryPriority` 맵 값(숫자) 오름차순으로 서브 목록 생성.
  List<String> _subOrderFromCategoryPriority(
      dynamic raw, Set<String> validSubs,) {
    if (raw is! Map) return [];

    final rows = <MapEntry<String, int>>[];
    for (final rawEntry in raw.entries) {
      final k = rawEntry.key;
      final v = rawEntry.value;
      if (k is! String || v is! num) continue;
      final sub = k.trim();
      if (!validSubs.contains(sub)) continue;
      rows.add(MapEntry(sub, v.round()));
    }
    if (rows.isEmpty) return [];
    rows.sort((a, b) => a.value.compareTo(b.value));

    final out = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      if (seen.add(row.key)) out.add(row.key);
    }
    return out;
  }

  /// `searchCategories` 배열 순서를 유지하되, 현재 선택에 없는 라벨은 제외.
  List<String> _subOrderFromSearchCategories(
      dynamic raw, Set<String> validSubs,) {
    if (raw is! List<dynamic>) return [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final sub = item.trim();
      if (!validSubs.contains(sub)) continue;
      if (seen.add(sub)) out.add(sub);
    }
    return out;
  }

  void _hydrateMatchingFields(Map<String, dynamic> doc) {
    final av = doc['isAvailable'];
    _matchingIsAvailable = av is bool ? av : true;

    final normalized = PoRegionFields.fromUserMap(doc);
    _matchingRegions.clear();
    if (normalized.regionFull.isNotEmpty) {
      _matchingRegions.add(normalized.regionFull);
    } else {
      final reg = doc['regions'];
      if (reg is List<dynamic>) {
        _matchingRegions.addAll(
          reg
              .whereType<String>()
              .map((String s) => s.trim())
              .where((String s) => s.isNotEmpty),
        );
      }
    }

    final pr = doc['priceRange'];
    _matchingPriceRange = pr is String ? pr.trim() : '';

    final rs = doc['responseSpeed'];
    _matchingResponseSpeed = rs is String ? rs.trim() : '';
  }

  /// 체크 집합이 바뀐 뒤 서브 순서 유지 · 신규는 맨 뒤.
  void _syncOrderedSubLabels(Set<String> newKeys) {
    final subs = ServiceCategoryCatalog.distinctSubs(newKeys);
    _orderedSubLabels.removeWhere((String s) => !subs.contains(s));
    for (final s in subs) {
      if (!_orderedSubLabels.contains(s)) {
        _orderedSubLabels.add(s);
      }
    }
  }

  List<String> _buildSearchCategories() =>
      List<String>.from(_orderedSubLabels);

  String _computePrimaryCategory() =>
      _orderedSubLabels.isEmpty ? '' : _orderedSubLabels.first;

  Map<String, int> _buildCategoryPriority() => <String, int>{
        for (var i = 0; i < _orderedSubLabels.length; i++)
          _orderedSubLabels[i]: i + 1,
      };

  void _toggleServiceSelection(String main, String sub, bool selected) {
    setState(() {
      _selectedServiceKeys = ServiceCategoryCatalog.toggledSelectionSet(
        current: _selectedServiceKeys,
        main: main,
        sub: sub,
        selected: selected,
      );
      _syncOrderedSubLabels(_selectedServiceKeys);
    });
  }

  Widget _buildConstructionAreasSection(TextTheme textTheme) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        dividerColor: Colors.grey.shade200,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0;
                  i < ServiceCategoryCatalog.mainTitles.length;
                  i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200,
                  ),
                _ConstructionMainCategoryTile(
                  mainTitle: ServiceCategoryCatalog.mainTitles[i],
                  selectedKeys: _selectedServiceKeys,
                  accent: _accent,
                  textTheme: textTheme,
                  onToggle: _toggleServiceSelection,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _persistUserProfileFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('저장할 수 없습니다. 로그인이 필요합니다.');
    }

    final mainCategories =
        ServiceCategoryCatalog.buildMainCategoriesList(_selectedServiceKeys);
    final serviceCategories =
        ServiceCategoryCatalog.buildServiceMaps(_selectedServiceKeys);

    final searchCategories = _buildSearchCategories();
    final primaryCategory = _computePrimaryCategory();
    final categoryPriority = _buildCategoryPriority();

    final regionLine = _matchingRegions
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .join(' ');
    final regionPack = PoRegionFields.fromRegionFull(regionLine);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, Object?>{
        'bizRegNumber': _bizRegNumberController.text.trim(),
        'businessName': _businessNameController.text.trim(),
        'representativeName': _repNameController.text.trim(),
        'businessPhone': _businessPhoneController.text.trim(),
        'storeName': _storeNameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'appDisplayName': _appDisplayNameController.text.trim(),
        if (user.email != null && user.email!.trim().isNotEmpty)
          'email': user.email!.trim(),
        'mainCategories': mainCategories,
        'serviceCategories': serviceCategories,
        'searchCategories': searchCategories,
        'primaryCategory': primaryCategory,
        'categoryPriority': categoryPriority,
        'isAvailable': _matchingIsAvailable,
        ...poRegionUserFirestoreMap(regionPack),
        'priceRange': _matchingPriceRange,
        'responseSpeed': _matchingResponseSpeed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _saveProfileTap() async {
    FocusScope.of(context).unfocus();
    if (!context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    bool dialogOpen = false;
    Object? caught;

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
      await _persistUserProfileFirestore();
    } on Object catch (e) {
      caught = e;
    } finally {
      if (dialogOpen && context.mounted) {
        navigator.pop();
      }
    }

    if (!context.mounted) return;
    final msg =
        caught == null ? '저장했습니다' : '저장하지 못했습니다: $caught';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _businessNameController.removeListener(_onProfileFieldChanged);
    _storeNameController.removeListener(_onProfileFieldChanged);
    _repNameController.removeListener(_onProfileFieldChanged);
    _nicknameController.removeListener(_onProfileFieldChanged);
    _loginEmailController.dispose();
    _googleNameController.dispose();
    _bizRegNumberController.dispose();
    _businessNameController.dispose();
    _repNameController.dispose();
    _businessPhoneController.dispose();
    _storeNameController.dispose();
    _nicknameController.dispose();
    _appDisplayNameController.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String title, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        title,
        style: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildAvatarHeader(TextTheme textTheme) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    return Center(
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.person_outline_rounded,
                      size: 44,
                      color: Colors.grey.shade500,
                    ),
                  )
                : Icon(
                    Icons.storefront_outlined,
                    size: 44,
                    color: Colors.grey.shade500,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            '프로필 사진 · 로고',
            style: textTheme.labelMedium?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
          MyApp.appBarTitle,
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
                  _buildAvatarHeader(textTheme),
                  const SizedBox(height: 20),
                  _sectionLabel('[로그인 계정 정보]', textTheme),
                  TextField(
                    readOnly: true,
                    enableInteractiveSelection: true,
                    controller: _loginEmailController,
                    decoration: _readonlyFieldDecoration(
                      label: '로그인 이메일',
                      hint: 'Google 로그인 계정',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    readOnly: true,
                    enableInteractiveSelection: true,
                    controller: _googleNameController,
                    decoration: _readonlyFieldDecoration(
                      label: 'Google 이름',
                      hint: '표시 이름',
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('[사업자 인증 정보]', textTheme),
                  TextField(
                    controller: _bizRegNumberController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '사업자등록번호',
                      hint: '000-00-00000',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _businessNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '사업자명',
                      hint: '등록 상호 입력',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _repNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '대표자명',
                      hint: '대표자 이름',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _businessPhoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '휴대폰번호',
                      hint: '예: 010-0000-0000',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '사업자 인증',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_businessVerificationStatusNormalized == 'verified') ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: poVerifiedCompanyBadgeChip(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    poBusinessVerificationMyPageLine(
                      _businessVerificationStatusNormalized,
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_businessVerificationStatusNormalized == 'rejected' &&
                      _businessVerificationRejectReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          '반려 사유: $_businessVerificationRejectReason',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_businessVerificationStatusNormalized == 'pending') ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            '심사중',
                            style: textTheme.labelMedium?.copyWith(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_businessVerificationStatusNormalized == 'unverified' ||
                      _businessVerificationStatusNormalized == 'rejected')
                    OutlinedButton(
                      onPressed: () {
                        runWithBriefLoading(context, () {
                          if (!context.mounted) return;
                          Navigator.of(context).push(poSmoothPushRoute<void>(
                            const BusinessVerificationScreen(),
                          ));
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: BorderSide(
                          color: _accent.withValues(alpha: 0.45),
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _businessVerificationStatusNormalized == 'rejected'
                            ? '재신청하기'
                            : '사업자 인증 신청',
                      ),
                    ),
                  const SizedBox(height: 22),
                  _sectionLabel('[매장/브랜드 정보]', textTheme),
                  TextField(
                    controller: _storeNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '매장이름',
                      hint: '매장 상호 또는 지점명',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '별명',
                      hint: '앱에서 부를 이름',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    readOnly: true,
                    controller: _appDisplayNameController,
                    decoration: _readonlyFieldDecoration(
                      label: '앱 표시 이름',
                      hint: '위 항목 기준으로 자동 계산됩니다',
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('[시공 분야]', textTheme),
                  Text(
                    '메인을 탭해서 펼치고, 세부 분야를 체크하면 바로 반영됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildConstructionAreasSection(textTheme),
                  const SizedBox(height: 22),
                  _sectionLabel('[마감 디테일]', textTheme),
                  Text(
                    '시공 마감 기준·사진을 등록하면 업체 프로필에 노출됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      runWithBriefLoading(context, () {
                        if (!context.mounted) return;
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          const FinishDetailCreateScreen(),
                        ));
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: const Text('마감 디테일 등록'),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final profileUid =
                          FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (profileUid.isEmpty) return const SizedBox.shrink();
                      return FinishDetailsListWidget(
                        userId: profileUid,
                        editable: true,
                      );
                    },
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
                onPressed: _saveProfileTap,
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
                child: const Text('정보 저장'),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
