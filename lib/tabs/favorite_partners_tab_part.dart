part of '../main.dart';

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchPartnersByUidChunked(
    Iterable<String> ids,) async {
  final list = ids
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  if (list.isEmpty) return [];

  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  const step = 10;
  for (var i = 0; i < list.length; i += step) {
    final chunk = list.sublist(i, math.min(i + step, list.length));
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    out.addAll(qs.docs);
  }
  final order = <String, int>{
    for (var j = 0; j < list.length; j++) list[j]: j,
  };
  out.sort(
    (QueryDocumentSnapshot<Map<String, dynamic>> a,
            QueryDocumentSnapshot<Map<String, dynamic>> b,) =>
        (order[a.id] ?? 0).compareTo(order[b.id] ?? 0),
  );
  return out;
}

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchCollaborationRequestsByIdChunked(
    Iterable<String> ids,) async {
  final list = ids
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  if (list.isEmpty) return [];

  final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  const step = 10;
  for (var i = 0; i < list.length; i += step) {
    final chunk = list.sublist(i, math.min(i + step, list.length));
    final qs = await FirebaseFirestore.instance
        .collection('collaborationRequests')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    out.addAll(qs.docs);
  }
  final order = <String, int>{
    for (var j = 0; j < list.length; j++) list[j]: j,
  };
  out.sort(
    (QueryDocumentSnapshot<Map<String, dynamic>> a,
            QueryDocumentSnapshot<Map<String, dynamic>> b,) =>
        (order[a.id] ?? 0).compareTo(order[b.id] ?? 0),
  );
  return out;
}

Future<void> _launchBusinessPhone(Uri uri) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  }
}

// ---------------------------------------------------------------------------
// 업체 전화 UX 헬퍼
// ---------------------------------------------------------------------------

/// 전화 옵션 항목 (라벨 + 번호 쌍).
class _BusinessPhoneOption {
  const _BusinessPhoneOption({required this.label, required this.number});
  final String label;
  final String number;
}

/// 문서 데이터에서 전화 옵션 목록 추출.
///
/// - storePhone / mobilePhone / virtualPhone 우선 확인
/// - 셋 다 없으면 phone → phoneNumber → businessPhone fallback
/// - 필드 자체가 없거나(null), String 이 아닌 타입이어도 crash 없이 '' 처리
List<_BusinessPhoneOption> _extractBusinessPhoneOptions(
    Map<String, dynamic> d) {
  /// 키가 없거나 null이면 '', String이 아닌 타입도 '' 반환.
  String s(String key) {
    final v = d[key];
    return (v is String) ? v.trim() : '';
  }

  final opts = <_BusinessPhoneOption>[];
  final store = s('storePhone');
  final mobile = s('mobilePhone');
  final virtual = s('virtualPhone');

  if (store.isNotEmpty) {
    opts.add(_BusinessPhoneOption(label: '매장으로 전화', number: store));
  }
  if (mobile.isNotEmpty) {
    opts.add(_BusinessPhoneOption(label: '휴대폰으로 전화', number: mobile));
  }
  if (virtual.isNotEmpty) {
    opts.add(_BusinessPhoneOption(label: '대표번호로 전화', number: virtual));
  }

  if (opts.isEmpty) {
    for (final key in const ['phone', 'phoneNumber', 'businessPhone']) {
      final raw = s(key);
      if (raw.isNotEmpty) {
        opts.add(_BusinessPhoneOption(label: '전화하기', number: raw));
        break;
      }
    }
  }
  return opts;
}

/// 업체 전화 연결 UX.
///
/// - storePhone + mobilePhone 둘 다 있으면 → bottom sheet 선택
/// - 하나만 있으면 → 바로 연결
/// - 없으면 → "등록된 전화번호가 없습니다" 스낵바
///
/// 모든 경로에서 [context.mounted] 및 sanitized 번호 유효성을 검증한다.
Future<void> poShowBusinessPhoneSheet(
    BuildContext context, Map<String, dynamic> data) async {
  final opts = _extractBusinessPhoneOptions(data);

  if (opts.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('등록된 전화번호가 없습니다.')),
    );
    return;
  }

  if (opts.length == 1) {
    final sanitized = opts.first.number.replaceAll(RegExp(r'[^\d+]'), '');
    if (sanitized.isEmpty) return;
    await _launchBusinessPhone(Uri.parse('tel:$sanitized'));
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '전화 연결',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...opts.map(
              (opt) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call_outlined),
                  label: Text(opt.label),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF007AFF),
                    side: BorderSide(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.45),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final sanitized =
                        opt.number.replaceAll(RegExp(r'[^\d+]'), '');
                    if (sanitized.isEmpty) return;
                    await _launchBusinessPhone(Uri.parse('tel:$sanitized'));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class FavoritePartnersTabScreen extends StatelessWidget {
  const FavoritePartnersTabScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text('로그인 후 이용할 수 있습니다.'),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, userSnap) {
          if (userSnap.hasError) {
            poReportFirestoreSnapshotError(
              'favorite_partners_user_doc',
              userSnap.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }
          final partnerRaw = userSnap.data?.data()?['favoritePartnerUids'];
          final partnerIds = partnerRaw is Iterable
              ? partnerRaw
                  .whereType<String>()
                  .map((String s) => s.trim())
                  .where((String s) => s.isNotEmpty)
                  .toList(growable: false)
              : <String>[];

          final reqRaw = userSnap.data?.data()?['favoriteRequestIds'];
          final requestIds = reqRaw is Iterable
              ? reqRaw
                  .whereType<String>()
                  .map((String s) => s.trim())
                  .where((String s) => s.isNotEmpty)
                  .toList(growable: false)
              : <String>[];

          if (partnerIds.isEmpty && requestIds.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '즐겨찾기한 업체와 구인·협업 공고가 없습니다.\n목록에서 별표를 눌러 추가해 주세요.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.45,
                  ),
                ),
              ),
            );
          }

          final favReqSet = requestIds.toSet();
          final future = Future.wait(<Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>[
            _fetchPartnersByUidChunked(partnerIds),
            _fetchCollaborationRequestsByIdChunked(requestIds),
          ]);

          return FutureBuilder<List<List<QueryDocumentSnapshot<Map<String, dynamic>>>>>(
            future: future,
            builder: (context, fb) {
              if (fb.connectionState == ConnectionState.waiting &&
                  !fb.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (fb.hasError) {
                poReportFirestoreSnapshotError(
                  'favorite_partners_fetch',
                  fb.error!,
                );
                return Center(
                  child: poFirestoreUserErrorPlaceholder(context),
                );
              }
              final lists = fb.data;
              final partnerDocs =
                  lists == null || lists.isEmpty ? <QueryDocumentSnapshot<Map<String, dynamic>>>[] : lists[0];
              final requestDocs =
                  lists == null || lists.length < 2 ? <QueryDocumentSnapshot<Map<String, dynamic>>>[] : lists[1];

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '즐겨찾기 업체',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  if (partnerDocs.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: const SliverToBoxAdapter(
                        child: Text('즐겨찾기한 업체가 없습니다.'),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.separated(
                        itemCount: partnerDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final docSnap = partnerDocs[i];
                          final d = docSnap.data();
                          final docId = docSnap.id;

                          final displayName = _matchingUserDisplayName(d);
                          final regions = _matchingUserRegionsLine(d);
                          final primary =
                              _matchingFieldStr(d['primaryCategory']);
                          final catsJoined =
                              _matchingUserSearchCategories(d).join(' · ');
                          final price = _matchingFieldStr(d['priceRange']);
                          final resp = _matchingFieldStr(d['responseSpeed']);
                          final phoneRaw = poUserPrimaryPhone(d);

                          return DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(13),
                                onTap: () {
                                  Navigator.of(ctx).push(poSmoothPushRoute<void>(
                                    CompanyDetailScreen(
                                      partnerUid: docId,
                                      userData: Map<String, dynamic>.from(d),
                                    ),
                                  ));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 14, 14, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              displayName,
                                              style: textTheme.titleSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          if (poBusinessVerificationShowVerifiedBadge(d))
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(right: 4),
                                              child: poVerifiedCompanyBadgeChip(
                                                  fontSize: 10),
                                            ),
                                          Icon(Icons.star_rounded,
                                              color: _accent, size: 22),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.place_outlined,
                                              size: 16,
                                              color: Colors.grey.shade600),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              regions,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                      color: Colors
                                                          .grey.shade700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (primary.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          primary,
                                          style: textTheme.labelMedium
                                              ?.copyWith(
                                            color: _accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (catsJoined.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          catsJoined,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade800,
                                            height: 1.35,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            '가성비 · ${price.isEmpty ? '-' : price}',
                                            style: textTheme.labelSmall
                                                ?.copyWith(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          Text(
                                            '응답 · ${resp.isEmpty ? '-' : resp}',
                                            style: textTheme.labelSmall
                                                ?.copyWith(
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: phoneRaw.isEmpty
                                                  ? () {
                                                      ScaffoldMessenger.of(ctx)
                                                          .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '등록된 전화번호가 없습니다.',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  : () {
                                                      final sanitized =
                                                          phoneRaw.replaceAll(
                                                              RegExp(
                                                                  r'[^\d+]'),
                                                              '');
                                                      _launchBusinessPhone(
                                                          Uri.parse(
                                                              'tel:$sanitized'));
                                                    },
                                              icon: Icon(Icons.call_outlined,
                                                  color: _accent, size: 18),
                                              label: const Text('전화하기'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: _accent,
                                                side: BorderSide(
                                                    color: _accent.withValues(
                                                        alpha: 0.45)),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: FilledButton(
                                              onPressed: () {
                                              runWithBriefLoading(ctx, () {
                                                if (!ctx.mounted) return;
                                                Navigator.of(ctx).push(
                                                    poSmoothPushRoute<void>(
                                                  ChatScreen(
                                                    requestId: 'direct',
                                                    partnerUid: docId,
                                                    requestTitle:
                                                        '$displayName · 문의',
                                                    partnerDisplayName:
                                                        displayName,
                                                  ),
                                                ));
                                              });
                                              },
                                              style: FilledButton.styleFrom(
                                                backgroundColor: _accent,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10),
                                              ),
                                              child: const Text('채팅하기'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              toggleFavoritePartnerUidForMe(
                                            ctx,
                                            docId,
                                          ),
                                          icon: Icon(Icons.star_border_rounded,
                                              color: _accent),
                                          label: const Text('즐겨찾기 해제'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: _accent,
                                            side: BorderSide(
                                                color: _accent.withValues(
                                                    alpha: 0.45)),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 10),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        '즐겨찾기 구인·협업',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  if (requestDocs.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: const SliverToBoxAdapter(
                        child: Text('즐겨찾기한 공고가 없습니다.'),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: requestDocs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          return _collaborationFeedListCard(
                            ctx,
                            requestDocs[i],
                            favoriteRequestIds: favReqSet,
                          );
                        },
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom:
                          poMainShellTabScrollBottomPadding(context),
                    ),
                    sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
