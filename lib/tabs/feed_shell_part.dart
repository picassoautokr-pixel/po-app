part of '../main.dart';

class _FeedMainSpec {
  const _FeedMainSpec({required this.chipLabel, required this.catalogMain});

  final String chipLabel;
  final String catalogMain;
}

const List<_FeedMainSpec> _kFeedMainSpecs = <_FeedMainSpec>[
  _FeedMainSpec(
    chipLabel: '외장 시공',
    catalogMain: ServiceCategoryCatalog.exteriorMainTitle,
  ),
  _FeedMainSpec(
    chipLabel: '필름 시공',
    catalogMain: ServiceCategoryCatalog.filmMainTitle,
  ),
  _FeedMainSpec(chipLabel: '전장 시공', catalogMain: '전장 시공'),
  _FeedMainSpec(chipLabel: '실내 시공', catalogMain: '실내 시공'),
  _FeedMainSpec(
    chipLabel: '튜닝 & 퍼포먼스',
    catalogMain: '튜닝 & 퍼포먼스',
  ),
  _FeedMainSpec(chipLabel: '정비 & 경정비', catalogMain: '정비 & 경정비'),
  _FeedMainSpec(chipLabel: '특수 시공', catalogMain: '특수 시공'),
  _FeedMainSpec(
    chipLabel: '사고 수리 & 보험',
    catalogMain: '사고 수리 & 보험',
  ),
];

/// [ServiceCategoryCatalog.mainTitles] 순으로 메인을 순회해 세부 항목 합침. 서브 라벨 중복 제거.
List<({String main, String sub})> _feedSubChipEntriesMerged(
  Set<String> selectedMains,
) {
  final Iterable<String> mainsToWalk;
  if (selectedMains.isEmpty) {
    mainsToWalk = ServiceCategoryCatalog.mainTitles;
  } else {
    mainsToWalk = ServiceCategoryCatalog.mainTitles
        .where(selectedMains.contains);
  }

  final seenSubs = <String>{};
  final out = <({String main, String sub})>[];
  for (final main in mainsToWalk) {
    for (final sub in ServiceCategoryCatalog.servicesForMain(main)) {
      if (seenSubs.add(sub)) {
        out.add((main: main, sub: sub));
      }
    }
  }
  return out;
}

bool _feedSubKeySelectedAnyMain(Set<String> selectedSubKeys, String sub) {
  final t = sub.trim();
  if (t.isEmpty) return false;
  for (final raw in selectedSubKeys) {
    final p = ServiceCategoryCatalog.splitSelectionKey(raw);
    if (p != null && p.sub == t) return true;
  }
  return false;
}

bool _feedKeepSubKeyDespiteMain(
  String main,
  String sub,
  Set<String> selectedMains,
) {
  if (selectedMains.contains(main)) return true;
  final twin = ServiceCategoryCatalog.pairedExteriorFilmMain(main);
  if (twin != null &&
      selectedMains.contains(twin) &&
      ServiceCategoryCatalog.mirrorsAcrossExteriorAndFilm(sub)) {
    return true;
  }
  return false;
}

void _feedPruneSubKeysForSelectedMains(
  Set<String> selectedMains,
  Set<String> subKeysMutable,
) {
  if (selectedMains.isEmpty) return;
  subKeysMutable.removeWhere((k) {
    final p = ServiceCategoryCatalog.splitSelectionKey(k);
    if (p == null) return true;
    return !_feedKeepSubKeyDespiteMain(p.main, p.sub, selectedMains);
  });
}

/// 홈 상단 요약: 예) `선택: 외장 시공, 필름 시공 / PPF, 랩핑` · 비어 있으면 `전체 시공분야`.
String _feedPublicSummaryLine(Set<String> mains, Set<String> subKeys) {
  final mainLabels = <String>[
    for (final spec in _kFeedMainSpecs)
      if (mains.contains(spec.catalogMain)) spec.chipLabel,
  ];
  final subs = ServiceCategoryCatalog.distinctSubs(subKeys).toList()
    ..sort();
  if (mainLabels.isEmpty && subs.isEmpty) return '전체 시공분야';
  final mPart = mainLabels.join(', ');
  final sPart = subs.join(', ');
  if (mPart.isEmpty) return '선택: $sPart';
  if (sPart.isEmpty) return '선택: $mPart';
  return '선택: $mPart / $sPart';
}

Future<void> showPoServiceCategoryFilterSheet({
  required BuildContext context,
  required Color accent,
  required Set<String> initialMains,
  required Set<String> initialSubKeys,
  required void Function(Set<String> mains, Set<String> subKeys) onApply,
  required VoidCallback onResetAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final viewInsets = MediaQuery.viewInsetsOf(ctx);
      final h = MediaQuery.sizeOf(ctx).height;
      final sheetH = (h * 0.8).clamp(320.0, h);
      return Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SizedBox(
          height: sheetH,
          child: PoServiceCategoryFilterSheet(
            accent: accent,
            initialMains: initialMains,
            initialSubKeys: initialSubKeys,
            onApply: onApply,
            onResetAll: onResetAll,
          ),
        ),
      );
    },
  );
}

class PoServiceCategoryFilterSheet extends StatefulWidget {
  const PoServiceCategoryFilterSheet({
    super.key,
    required this.accent,
    required this.initialMains,
    required this.initialSubKeys,
    required this.onApply,
    required this.onResetAll,
  });

  final Color accent;
  final Set<String> initialMains;
  final Set<String> initialSubKeys;
  final void Function(Set<String> mains, Set<String> subKeys) onApply;
  final VoidCallback onResetAll;

  @override
  State<PoServiceCategoryFilterSheet> createState() =>
      _PoServiceCategoryFilterSheetState();
}

class _PoServiceCategoryFilterSheetState
    extends State<PoServiceCategoryFilterSheet> {
  late Set<String> _draftMains;
  late Set<String> _draftSubs;

  @override
  void initState() {
    super.initState();
    _draftMains = Set<String>.from(widget.initialMains);
    _draftSubs = Set<String>.from(widget.initialSubKeys);
  }

  void _onSelectAllTap() {
    setState(() {
      _draftMains.clear();
      _draftSubs.clear();
    });
  }

  void _toggleMain(String catalogMain) {
    setState(() {
      if (_draftMains.contains(catalogMain)) {
        _draftMains.remove(catalogMain);
      } else {
        _draftMains.add(catalogMain);
      }
      _feedPruneSubKeysForSelectedMains(_draftMains, _draftSubs);
    });
  }

  void _toggleSub(String sub, String main) {
    setState(() {
      var anyKeyForSub = false;
      for (final raw in _draftSubs) {
        final p = ServiceCategoryCatalog.splitSelectionKey(raw);
        if (p != null && p.sub == sub) {
          anyKeyForSub = true;
          break;
        }
      }
      final nowSelect = !anyKeyForSub;
      final next = ServiceCategoryCatalog.toggledSelectionSet(
        current: _draftSubs,
        main: main,
        sub: sub,
        selected: nowSelect,
      );
      _draftSubs
        ..clear()
        ..addAll(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = widget.accent;
    final subEntries = _feedSubChipEntriesMerged(_draftMains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () {
                  widget.onResetAll();
                  Navigator.of(context).pop();
                },
                child: Text(
                  '선택 초기화',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '시공분야 선택',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () {
                  widget.onApply(
                    Set<String>.from(_draftMains),
                    Set<String>.from(_draftSubs),
                  );
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text('적용'),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.grey.shade200),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '메인 카테고리 (다중 선택)',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('전체보기'),
                      selected: _draftMains.isEmpty,
                      showCheckmark: false,
                      onSelected: (_) => _onSelectAllTap(),
                      selectedColor: accent,
                      backgroundColor: Colors.white,
                      checkmarkColor: Colors.white,
                      labelStyle: textTheme.labelLarge?.copyWith(
                        color: _draftMains.isEmpty ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      side: BorderSide(
                        color: _draftMains.isEmpty
                            ? accent
                            : Colors.grey.shade400,
                        width: _draftMains.isEmpty ? 1.4 : 1,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    for (final spec in _kFeedMainSpecs)
                      FilterChip(
                        label: Text(spec.chipLabel),
                        selected:
                            _draftMains.contains(spec.catalogMain),
                        showCheckmark: false,
                        onSelected: (_) => _toggleMain(spec.catalogMain),
                        selectedColor: accent,
                        backgroundColor: Colors.white,
                        checkmarkColor: Colors.white,
                        labelStyle: textTheme.labelLarge?.copyWith(
                          color: _draftMains.contains(spec.catalogMain)
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color: _draftMains.contains(spec.catalogMain)
                              ? accent
                              : Colors.grey.shade400,
                          width:
                              _draftMains.contains(spec.catalogMain) ? 1.4 : 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  '세부 시공 (다중 선택)',
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _draftMains.isEmpty
                      ? '전체 메인 기준 세부 항목입니다.'
                      : '선택한 메인에 해당하는 세부만 표시됩니다.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                if (subEntries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '표시할 세부 항목이 없습니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subEntries.map((entry) {
                      final sel = _feedSubKeySelectedAnyMain(
                        _draftSubs,
                        entry.sub,
                      );
                      return FilterChip(
                        showCheckmark: false,
                        label: Text(entry.sub),
                        selected: sel,
                        selectedColor: accent,
                        backgroundColor: Colors.white,
                        checkmarkColor: Colors.white,
                        onSelected: (_) =>
                            _toggleSub(entry.sub, entry.main),
                        labelStyle: textTheme.labelLarge?.copyWith(
                          color: sel ? Colors.white : Colors.black87,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                        side: BorderSide(
                          color:
                              sel ? accent : Colors.grey.shade400,
                          width: sel ? 1.4 : 1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 홈·구인·협업 공통 상단 (1행: 지역·즐겨찾기·알림·프로필 / 2행: 시공분야·검색 / 요약).
class PoMainListHeader extends StatelessWidget {
  const PoMainListHeader({
    super.key,
    required this.accent,
    required this.regionLabel,
    required this.onRegionTap,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onNotificationTap,
    required this.onProfileTap,
    required this.favoritesOnly,
    required this.onFavoritesOnlyChanged,
    required this.selectedMainCategories,
    required this.selectedSubKeys,
    required this.onOpenCategoryFilter,
  });

  final Color accent;
  final String regionLabel;
  final VoidCallback onRegionTap;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onSearchChanged;
  final VoidCallback onSearchClear;
  final VoidCallback onNotificationTap;
  final VoidCallback onProfileTap;
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final Set<String> selectedMainCategories;
  final Set<String> selectedSubKeys;
  final VoidCallback onOpenCategoryFilter;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = _feedPublicSummaryLine(
      selectedMainCategories,
      selectedSubKeys,
    );
    final hasSearchText = searchController.text.trim().isNotEmpty;

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                InkWell(
                  onTap: onRegionTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined, size: 20, color: accent),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            regionLabel,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.expand_more_rounded,
                            color: Colors.grey.shade600),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '즐겨찾기만 보기',
                  onPressed: () =>
                      onFavoritesOnlyChanged(!favoritesOnly),
                  icon: Icon(
                    favoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
                    color: favoritesOnly ? accent : Colors.grey.shade700,
                  ),
                ),
                IconButton(
                  tooltip: '알림',
                  onPressed: onNotificationTap,
                  icon: Icon(Icons.notifications_none_rounded, color: accent),
                ),
                IconButton(
                  tooltip: '마이페이지',
                  onPressed: onProfileTap,
                  icon: Icon(Icons.person_outline_rounded, color: accent),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onOpenCategoryFilter,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '시공분야',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => onSearchChanged(),
                    style: textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '검색',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      suffixIcon: hasSearchText
                          ? IconButton(
                              tooltip: '검색어 지우기',
                              icon: Icon(
                                Icons.clear_rounded,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: onSearchClear,
                            )
                          : null,
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
                        borderSide: BorderSide(color: accent, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tune_rounded, size: 20, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        summary,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.black87,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
