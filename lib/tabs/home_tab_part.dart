part of '../main.dart';

Set<String> _inferSubLabelsForMain(String catalogMain, String haystackLower) {
  final out = <String>{};
  for (final sub in ServiceCategoryCatalog.servicesForMain(catalogMain)) {
    if (haystackLower.contains(sub.toLowerCase())) {
      out.add(sub);
    }
  }
  return out;
}

Set<String> _docSubsForMainFilter(
  Map<String, dynamic> d,
  String catalogMain,
) {
  final fromKeys = <String>{};
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  for (final k in keys) {
    final parsed = ServiceCategoryCatalog.splitSelectionKey(k);
    if (parsed != null && parsed.main == catalogMain) {
      fromKeys.add(parsed.sub);
    }
  }
  if (fromKeys.isNotEmpty) return fromKeys;

  final rawList = d['serviceCategories'];
  if (rawList is List<dynamic>) {
    final onlyStrings = <String>{};
    for (final e in rawList) {
      if (e is String && e.trim().isNotEmpty) onlyStrings.add(e.trim());
    }
    if (onlyStrings.isNotEmpty) {
      final docMain = _collaborationRequestString(d['mainCategory']);
      final m = catalogMain.trim();
      if (m.isEmpty) return onlyStrings;
      if (docMain.isEmpty) return onlyStrings;
      final a = docMain.toLowerCase();
      final b = m.toLowerCase();
      if (a == b || a.contains(b) || b.contains(a)) return onlyStrings;
    }
  }

  final hay = '${_collaborationRequestString(d['workType'])} '
          '${_collaborationRequestString(d['description'])} '
      .toLowerCase();
  return _inferSubLabelsForMain(catalogMain, hay);
}

bool _userDocRegionMatches(Map<String, dynamic> d, String regionFilter) {
  return poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromUserMap(d),
    regionFilter,
  );
}

bool _mainLabelsLooselyMatch(String docLabel, String selectedMain) {
  final a = docLabel.trim().toLowerCase();
  final b = selectedMain.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  return a == b || a.contains(b) || b.contains(a);
}

bool _userListContainsAnyMainCat(
  Map<String, dynamic> d,
  Set<String> selectedMains,
) {
  if (selectedMains.isEmpty) return true;
  final raw = d['mainCategories'];
  if (raw is! List<dynamic>) return false;
  for (final e in raw) {
    if (e is! String) continue;
    final s = e.trim();
    if (s.isEmpty) continue;
    for (final m in selectedMains) {
      if (_mainLabelsLooselyMatch(s, m)) return true;
    }
  }
  return false;
}

bool _userSearchCategoriesMatchSubs(Map<String, dynamic> d, Set<String> subs) {
  if (subs.isEmpty) return true;
  final raw = d['searchCategories'];
  if (raw is! List<dynamic>) return false;
  final items = raw
      .whereType<String>()
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  for (final sub in subs) {
    final sl = sub.trim().toLowerCase();
    if (sl.isEmpty) continue;
    for (final it in items) {
      if (it.contains(sl) || sl.contains(it)) return true;
    }
  }
  return false;
}

String _homeUserKeywordBundle(Map<String, dynamic> d) {
  final regLine = _matchingUserRegionsLine(d);
  final po = PoRegionFields.fromUserMap(d);
  return [
    _matchingFieldStr(d['displayName']),
    _matchingFieldStr(d['businessName']),
    _matchingFieldStr(d['shopName']),
    _matchingFieldStr(d['ownerName']),
    _matchingFieldStr(d['region']),
    _matchingFieldStr(d['regionFull']),
    if (regLine != '-') regLine,
    po.regions.join(' '),
  ].join(' ').toLowerCase();
}

bool _userDocSubsFromServiceCategoriesContain(
    Map<String, dynamic> d, Set<String> distinctSubs,) {
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  final docSubs = ServiceCategoryCatalog.distinctSubs(keys);
  for (final s in distinctSubs) {
    final sl = s.trim();
    if (sl.isEmpty) continue;
    final slLower = sl.toLowerCase();
    for (final ds in docSubs) {
      final dl = ds.toLowerCase();
      if (dl == slLower || dl.contains(slLower) || slLower.contains(dl)) {
        return true;
      }
    }
  }
  return false;
}

bool _userMatchesServiceSubFilter(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  if (distinctSubs.isEmpty) return true;
  if (_userSearchCategoriesMatchSubs(d, distinctSubs)) return true;
  return _userDocSubsFromServiceCategoriesContain(d, distinctSubs);
}

String _collaborationKeywordBundle(Map<String, dynamic> d) {
  final po = PoRegionFields.fromCollaborationMap(d);
  return [
    _collaborationRequestString(d['title']),
    _collaborationRequestString(d['workType']),
    _collaborationRequestString(d['description']),
    _collaborationRequestString(d['location']),
    _matchingFieldStr(d['regionFull']),
    po.regions.join(' '),
  ].join(' ').toLowerCase();
}

bool _collabListSearchCategoriesMatchSubs(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  final raw = d['searchCategories'];
  if (raw is! List<dynamic>) return false;
  final items = raw
      .whereType<String>()
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  for (final sub in distinctSubs) {
    final sl = sub.trim().toLowerCase();
    if (sl.isEmpty) continue;
    for (final it in items) {
      if (it.contains(sl) || sl.contains(it)) return true;
    }
  }
  return false;
}

bool _collabMatchesSelectedSubs(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  if (distinctSubs.isEmpty) return true;
  if (_collabListSearchCategoriesMatchSubs(d, distinctSubs)) return true;

  final raw = d['serviceCategories'];
  final fromSc = <String>[];
  if (raw is List<dynamic>) {
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) fromSc.add(e.trim());
    }
  }
  for (final s in distinctSubs) {
    final sl = s.trim();
    if (sl.isEmpty) continue;
    final slLower = sl.toLowerCase();
    for (final c in fromSc) {
      final cl = c.toLowerCase();
      if (cl == slLower || cl.contains(slLower) || slLower.contains(cl)) {
        return true;
      }
    }
  }
  final wt = _collaborationRequestString(d['workType']).toLowerCase();
  for (final s in distinctSubs) {
    final sl = s.trim().toLowerCase();
    if (sl.isNotEmpty && wt.contains(sl)) return true;
  }
  return false;
}

bool _passesUserSearchFilters({
  required Map<String, dynamic> d,
  required String regionFilter,
  required String keywordApplied,
  required Set<String> selectedMainCategories,
  required Set<String> distinctSubs,
}) {
  if (!_userDocRegionMatches(d, regionFilter)) return false;

  if (!_userListContainsAnyMainCat(d, selectedMainCategories)) return false;

  if (!_userMatchesServiceSubFilter(d, distinctSubs)) return false;

  final kw = keywordApplied.trim();
  if (kw.isNotEmpty) {
    if (!_homeUserKeywordBundle(d).contains(kw.toLowerCase())) return false;
  }

  return true;
}

bool _collabDocHasAnyMainCategory(
  Map<String, dynamic> d,
  Set<String> mains,
) {
  if (mains.isEmpty) return true;
  final mc = _collaborationRequestString(d['mainCategory']);
  if (mc.isNotEmpty) {
    for (final m in mains) {
      if (_mainLabelsLooselyMatch(mc, m)) return true;
    }
  }
  final rawList = d['mainCategories'];
  if (rawList is List<dynamic>) {
    for (final e in rawList) {
      if (e is! String) continue;
      final s = e.trim();
      if (s.isEmpty) continue;
      for (final m in mains) {
        if (_mainLabelsLooselyMatch(s, m)) return true;
      }
    }
  }
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  for (final k in keys) {
    final p = ServiceCategoryCatalog.splitSelectionKey(k);
    if (p == null) continue;
    for (final m in mains) {
      if (_mainLabelsLooselyMatch(p.main, m)) return true;
    }
  }
  return false;
}

Set<String> _docSubsUnionForMains(
  Map<String, dynamic> d,
  Set<String> mains,
) {
  if (mains.isEmpty) {
    return ServiceCategoryCatalog.distinctSubs(
      ServiceCategoryCatalog.selectionKeysFromFirestore(
        serviceCategories: d['serviceCategories'],
      ),
    );
  }
  final u = <String>{};
  for (final m in mains) {
    u.addAll(_docSubsForMainFilter(d, m));
  }
  return u;
}

/// 비어 있으면 과거 데이터 호환을 위해 모집중으로 간주.
bool _collabOpenLikeStatus(dynamic statusField) {
  final s = _collaborationRequestString(statusField).trim().toLowerCase();
  if (s.isEmpty) return true;
  return s == 'open' || s == '모집중';
}

bool _passesHomeCollaborationFilters({
  required Map<String, dynamic> d,
  required String regionFilter,
  required String keywordApplied,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  if (!poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(d),
    regionFilter,
  )) {
    return false;
  }

  final kw = keywordApplied.trim();
  if (kw.isNotEmpty) {
    if (!_collaborationKeywordBundle(d).contains(kw.toLowerCase())) {
      return false;
    }
  }

  if (!_collabDocHasAnyMainCategory(d, selectedMainCategories)) {
    return false;
  }

  if (!_collabMatchesSelectedSubs(d, selectedSubLabels)) {
    return false;
  }

  return true;
}

int _responseSpeedSortRank(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('매우') || s.contains('빠름') || s.contains('빨')) return 0;
  if (s.contains('보통')) return 1;
  if (s.contains('느')) return 2;
  return 3;
}

int _priceRangeSortRank(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('저') || s.contains('낮')) return 0;
  if (s.contains('중')) return 1;
  if (s.contains('고') || s.contains('높')) return 2;
  return 3;
}

bool _userHasAnySubInSearchCategories(Map<String, dynamic> d, Set<String> subs) {
  if (subs.isEmpty) return true;
  return _userSearchCategoriesMatchSubs(d, subs);
}

DateTime? _firestoreAsDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  return null;
}

int _compareRecommendedUsers(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String regionFilter,
  required Set<String> distinctSubs,
}) {
  final ua = _matchingUserAvailable(a);
  final ub = _matchingUserAvailable(b);
  if (ua != ub) return ua ? -1 : 1;

  final ra = _userDocRegionMatches(a, regionFilter) ? 0 : 1;
  final rb = _userDocRegionMatches(b, regionFilter) ? 0 : 1;
  if (ra != rb) return ra.compareTo(rb);

  final sa = _userHasAnySubInSearchCategories(a, distinctSubs) ? 0 : 1;
  final sb = _userHasAnySubInSearchCategories(b, distinctSubs) ? 0 : 1;
  if (sa != sb) return sa.compareTo(sb);

  final fa = _responseSpeedSortRank(_matchingFieldStr(a['responseSpeed']));
  final fb = _responseSpeedSortRank(_matchingFieldStr(b['responseSpeed']));
  if (fa != fb) return fa.compareTo(fb);

  final pa = _priceRangeSortRank(_matchingFieldStr(a['priceRange']));
  final pb = _priceRangeSortRank(_matchingFieldStr(b['priceRange']));
  if (pa != pb) return pa.compareTo(pb);

  return 0;
}

int _compareRecommendedCollabs(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String regionFilter,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  final oa = _collaborationRequestString(a['status']);
  final ob = _collaborationRequestString(b['status']);
  final openA = _collabOpenLikeStatus(oa);
  final openB = _collabOpenLikeStatus(ob);
  if (openA != openB) return openA ? -1 : 1;

  final ma = poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(a),
    regionFilter,
  );
  final mb = poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(b),
    regionFilter,
  );
  if (ma != mb) return ma ? -1 : 1;

  bool hits(Map<String, dynamic> d, Set<String> filterSubs) {
    if (filterSubs.isEmpty) return true;
    final docSubs = _docSubsUnionForMains(d, selectedMainCategories);
    for (final sub in filterSubs) {
      if (docSubs.contains(sub)) return true;
      if (_collaborationRequestString(d['workType'])
          .toLowerCase()
          .contains(sub.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  final ha = hits(a, selectedSubLabels);
  final hb = hits(b, selectedSubLabels);
  if (ha != hb) return ha ? -1 : 1;

  final da = _firestoreAsDateTime(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
  final db = _firestoreAsDateTime(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
  return db.compareTo(da);
}

String _firestoreLoadErrorHint(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('index')) {
    return 'Firestore 색인 문제로 목록을 불러오지 못했습니다. 잠시 후 다시 시도하거나 관리자에게 문의해 주세요.';
  }
  return '목록을 불러오지 못했습니다. 네트워크 상태를 확인해 주세요.';
}

const Color _kHomeTabAccent = Color(0xFF007AFF);

Widget _homePartnerCard({
  required BuildContext context,
  required TextTheme textTheme,
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required Set<String> favoriteUids,
}) {
    final d = doc.data();
    final name = poHomeUserCardTitle(d);
    final regions = _matchingUserRegionsLine(d);
    final primary = _matchingFieldStr(d['primaryCategory']);
    final cats = _matchingUserSearchCategories(d);
    final catsJoined = cats.isEmpty ? '-' : cats.join(' · ');
    final price = _matchingFieldStr(d['priceRange']);
    final resp = _matchingFieldStr(d['responseSpeed']);
    final phoneRaw = poUserPrimaryPhone(d);
    final isFav = favoriteUids.contains(doc.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {
            Navigator.of(context).push(poSmoothPushRoute<void>(
              CompanyDetailScreen(
                partnerUid: doc.id,
                userData: Map<String, dynamic>.from(doc.data()),
              ),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기',
                      onPressed: () =>
                          toggleFavoritePartnerUidForMe(context, doc.id),
                      icon: Icon(
                        isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: _kHomeTabAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        regions,
                        style: textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                if (primary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    primary,
                    style: textTheme.labelMedium?.copyWith(
                      color: _kHomeTabAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  catsJoined,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade800,
                    height: 1.35,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 18, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '평점 ${_matchingFormatAverageRatingDisplay(d)}',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '예산 · ${price.isEmpty ? '-' : price}',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '응답 · ${resp.isEmpty ? '-' : resp}',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '위치',
                      icon: Icon(Icons.place_outlined, color: _kHomeTabAccent),
                      onPressed: regions == '-' || regions.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('지역: $regions')),
                              );
                            },
                    ),
                    IconButton(
                      tooltip: '전화',
                      icon: Icon(Icons.call_outlined, color: _kHomeTabAccent),
                      onPressed: phoneRaw.isEmpty
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('등록된 전화번호가 없습니다.'),
                                ),
                              );
                            }
                          : () {
                              final sanitized = phoneRaw
                                  .replaceAll(RegExp(r'[^\d+]'), '');
                              _launchBusinessPhone(Uri.parse('tel:$sanitized'));
                            },
                    ),
                    IconButton(
                      tooltip: '채팅',
                      icon: Icon(Icons.chat_bubble_outline_rounded,
                          color: _kHomeTabAccent),
                      onPressed: () {
                        runWithBriefLoading(context, () {
                          if (!context.mounted) return;
                          Navigator.of(context).push(poSmoothPushRoute<void>(
                            ChatScreen(
                              requestId: 'direct',
                              partnerUid: doc.id,
                              requestTitle: '$name · 문의',
                              partnerDisplayName: name,
                            ),
                          ));
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


/// 홈 탭: 업체 목록 (필터·카테고리는 [PoMainListHeader]).
class HomeTabScreen extends StatelessWidget {
  const HomeTabScreen({
    super.key,
    required this.regionFilter,
    required this.keyword,
    required this.selectedMainCategories,
    required this.subKeySet,
    required this.favoritesOnly,
  });

  final String regionFilter;
  final String keyword;
  final Set<String> selectedMainCategories;
  final Set<String> subKeySet;
  final bool favoritesOnly;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final distinctSubs = ServiceCategoryCatalog.distinctSubs(subKeySet);

    if (uid == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('업체 목록을 보려면 로그인해 주세요.'),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, meSnap) {
          final rawFav = meSnap.data?.data()?['favoritePartnerUids'];
          final fav = <String>{
            if (rawFav is Iterable)
              for (final e in rawFav)
                if (e is String && e.trim().isNotEmpty) e.trim(),
          };

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, userQs) {
              if (userQs.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _firestoreLoadErrorHint(userQs.error!),
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }
              if (userQs.connectionState == ConnectionState.waiting &&
                  !userQs.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var list = (userQs.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where(
                    (q) => _passesUserSearchFilters(
                      d: q.data(),
                      regionFilter: regionFilter,
                      keywordApplied: keyword,
                      selectedMainCategories: selectedMainCategories,
                      distinctSubs: distinctSubs,
                    ),
                  )
                  .toList();

              if (favoritesOnly) {
                list = list.where((q) => fav.contains(q.id)).toList();
              }

              list.sort(
                (a, b) => _compareRecommendedUsers(
                  a.data(),
                  b.data(),
                  regionFilter: regionFilter,
                  distinctSubs: distinctSubs,
                ),
              );

              if (list.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      favoritesOnly
                          ? '즐겨찾기한 업체가 없습니다.'
                          : '조건에 맞는 업체가 없습니다.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                        height: 1.45,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: list.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  return _homePartnerCard(
                    context: context,
                    textTheme: textTheme,
                    doc: list[i],
                    favoriteUids: fav,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


/// 검색 결과: 모집중·open 먼저, 그다음 상태명 사전순.
int _collabSortForSearch(Map<String, dynamic> a, Map<String, dynamic> b) {
  final sa = _collaborationRequestString(a['status']);
  final sb = _collaborationRequestString(b['status']);
  final oa = _collabOpenLikeStatus(sa);
  final ob = _collabOpenLikeStatus(sb);
  if (oa != ob) return oa ? -1 : 1;
  return sa.toLowerCase().compareTo(sb.toLowerCase());
}
