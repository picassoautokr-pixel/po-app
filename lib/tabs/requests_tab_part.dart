part of '../main.dart';

Future<Map<String, Map<String, dynamic>?>> _batchFetchCollaborationRequestsByIds(
  Iterable<String> requestIds,
) async {
  final out = <String, Map<String, dynamic>?>{};
  final ids = requestIds.map((String s) => s.trim()).where((String s) => s.isNotEmpty).toSet().toList();
  if (ids.isEmpty) return out;
  for (var i = 0; i < ids.length; i += 10) {
    final chunk =
        ids.sublist(i, math.min(i + 10, ids.length));
    try {
      final qs = await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in qs.docs) {
        out[d.id] = d.data();
      }
    } on Object catch (e, st) {
      poDebugFirestoreError('batchFetchCollaborationRequestsByIds', e, st);
    }
  }
  for (final id in ids) {
    out.putIfAbsent(id, () => null);
  }
  return out;
}

class MyRequestsTabScreen extends StatefulWidget {
  const MyRequestsTabScreen({super.key});

  @override
  State<MyRequestsTabScreen> createState() => _MyRequestsTabScreenState();
}

class _MyRequestsTabScreenState extends State<MyRequestsTabScreen> {
  int _segment = 0;
  CollaborationMyOutgoingFilterChip _outFilterChip =
      CollaborationMyOutgoingFilterChip.inProgress;

  static const Color _segAccent = Color(0xFF007AFF);

  static int _statusOrderKeyPosted(String statusRaw) {
    final s = collaborationDisplayStatusKo(
      statusRaw.trim().isEmpty ? 'open' : statusRaw,
    );
    const order = <String>[
      '모집중',
      '채택됨',
      '진행중',
      '완료',
      '마감',
      '취소',
    ];
    final i = order.indexOf(s);
    return i >= 0 ? i : order.length;
  }

  Widget _postedPanel(BuildContext context, String uid) {
    final textTheme = Theme.of(context).textTheme;

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('collaborationRequests')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, collabSnap) {
          if (collabSnap.connectionState == ConnectionState.waiting &&
              !collabSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (collabSnap.hasError) {
            poReportFirestoreSnapshotError(
              'my_requests_posted_list',
              collabSnap.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }

          final docs = collabSnap.data?.docs ?? [];
          final mine = docs
              .where(
                (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                    _collaborationRequestString(d.data()['ownerUid']) == uid,
              )
              .toList(growable: false);

          mine.sort((a, b) {
            final sa = _collaborationRequestString(a.data()['status']);
            final sb = _collaborationRequestString(b.data()['status']);
            final oa = _statusOrderKeyPosted(sa);
            final ob = _statusOrderKeyPosted(sb);
            if (oa != ob) return oa.compareTo(ob);
            final da =
                _firestoreAsDateTime(a.data()['createdAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            final db =
                _firestoreAsDateTime(b.data()['createdAt']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (mine.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '등록한 모집·협업 공고가 없습니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              poMainShellTabScrollBottomPadding(context),
            ),
            itemCount: mine.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              return _collaborationCardFromFirestoreDoc(
                ctx,
                mine[i],
                showCollaborationStatus: true,
              );
            },
          );
        },
      ),
    );
  }

  Widget _filterChipWrap(BuildContext context) {
    Widget chip(CollaborationMyOutgoingFilterChip v, String label) {
      final sel = _outFilterChip == v;
      return FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
            color: sel ? Colors.white : Colors.black87,
          ),
        ),
        selected: sel,
        selectedColor: _segAccent,
        checkmarkColor: Colors.white,
        backgroundColor: Colors.grey.shade100,
        onSelected: (_) {
          setState(() => _outFilterChip = v);
        },
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: sel ? _segAccent : Colors.grey.shade300,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(CollaborationMyOutgoingFilterChip.all, '전체'),
          chip(CollaborationMyOutgoingFilterChip.inProgress, '진행중'),
          chip(CollaborationMyOutgoingFilterChip.completed, '완료'),
          chip(CollaborationMyOutgoingFilterChip.rejected, '거절됨'),
        ],
      ),
    );
  }

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      '내가 올린 글',
                      maxLines: 1,
                      softWrap: false,
                      style: textTheme.labelLarge?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      '내가 지원한 글',
                      maxLines: 1,
                      softWrap: false,
                      style: textTheme.labelLarge?.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              selected: <int>{_segment},
              onSelectionChanged: (Set<int> s) {
                if (s.isEmpty) return;
                setState(() => _segment = s.first);
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                minimumSize: WidgetStateProperty.all(
                  const Size(0, 44),
                ),
                padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return Colors.black87;
                }),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _segAccent;
                  }
                  return Colors.grey.shade100;
                }),
              ),
            ),
          ),
          if (_segment == 1)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _filterChipWrap(context),
                  Expanded(
                    child: _MyOutgoingApplicationsList(
                      applicantUid: uid,
                      filterChip: _outFilterChip,
                      textTheme: textTheme,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(child: _postedPanel(context, uid)),
        ],
      ),
    );
  }
}

class _MyOutgoingApplicationsList extends StatefulWidget {
  const _MyOutgoingApplicationsList({
    required this.applicantUid,
    required this.filterChip,
    required this.textTheme,
  });

  final String applicantUid;
  final CollaborationMyOutgoingFilterChip filterChip;
  final TextTheme textTheme;

  @override
  State<_MyOutgoingApplicationsList> createState() =>
      _MyOutgoingApplicationsListState();
}

class _MyOutgoingApplicationsListState extends State<_MyOutgoingApplicationsList> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _appDocs = [];
  Map<String, Map<String, dynamic>?> _requestsById = {};
  Object? _error;
  bool _loadingRequests = false;
  bool _hasReceivedSnapshot = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _MyOutgoingApplicationsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.applicantUid != widget.applicantUid) {
      _subscription?.cancel();
      setState(() {
        _appDocs = [];
        _requestsById = {};
        _error = null;
        _hasReceivedSnapshot = false;
      });
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collectionGroup('applications')
        .where('applicantUid', isEqualTo: widget.applicantUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          _onApplicationsSnapshot,
          onError: (Object e, StackTrace st) {
            poDebugFirestoreError('my_outgoing_applications_stream', e, st);
            if (poFirestoreErrorIsFailedPrecondition(e)) {
              debugPrint(
                '[Firestore][my_outgoing_applications_stream] '
                '${collaborationApplicationsIndexHint()}',
              );
            }
            if (!mounted) return;
            setState(() {
              _error = e;
              _hasReceivedSnapshot = true;
              _loadingRequests = false;
            });
          },
        );
  }

  Future<void> _onApplicationsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final ids = <String>{};
    for (final d in snap.docs) {
      final DocumentReference<Map<String, dynamic>>? rid =
          d.reference.parent.parent;
      if (rid != null && rid.id.trim().isNotEmpty) ids.add(rid.id);
    }

    if (!mounted) return;
    setState(() {
      _loadingRequests = true;
      _error = null;
    });

    Map<String, Map<String, dynamic>?> reqMap = {};
    try {
      reqMap = ids.isEmpty ? {} : await _batchFetchCollaborationRequestsByIds(ids);
    } on Object catch (e, st) {
      poDebugFirestoreError('my_outgoing_applications_batch', e, st);
      if (poFirestoreErrorIsFailedPrecondition(e)) {
        debugPrint(
          '[Firestore][my_outgoing_applications_batch] '
          '${collaborationApplicationsIndexHint()}',
        );
      }
      if (!mounted) return;
      setState(() {
        _error = e;
        _hasReceivedSnapshot = true;
        _loadingRequests = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _appDocs = snap.docs;
      _requestsById = reqMap;
      _loadingRequests = false;
      _hasReceivedSnapshot = true;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _requestIdFromAppDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final p = d.reference.parent.parent;
    return p?.id.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = widget.textTheme;

    if (_error != null) {
      return Center(
        child: poFirestoreUserErrorPlaceholder(context),
      );
    }

    if (!_hasReceivedSnapshot) {
      return const Center(child: CircularProgressIndicator());
    }

    final filteredAppDocs =
        List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(_appDocs)
            .where(
              (
                QueryDocumentSnapshot<Map<String, dynamic>> doc,
              ) =>
                  collaborationMyOutgoingRowMatchesChip(
                applicationData: doc.data(),
                chip: widget.filterChip,
              ),
            )
            .toList();

    if (_appDocs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '지원한 공고가 없습니다.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    if (!_loadingRequests && filteredAppDocs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '표시할 지원 글이 없습니다.\n다른 상태 필터를 선택해 보세요.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade700,
              height: 1.45,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            poMainShellTabScrollBottomPadding(context),
          ),
          itemCount: filteredAppDocs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, index) {
            final appDoc = filteredAppDocs[index];
            final app = appDoc.data();
            final reqId = _requestIdFromAppDoc(appDoc);
            final req = reqId.isEmpty ? null : _requestsById[reqId];

            final ownerEmailLine =
                _collaborationRequestString(req?['ownerEmail']).trim();

            final titleReq = req == null
                ? '공고 (불러오는 중 또는 삭제됨)'
                : ((_collaborationRequestString(req['title']).isNotEmpty
                        ? _collaborationRequestString(req['title'])
                        : _collaborationDisplayTitle(req)));
            final region =
                req == null
                    ? '-'
                    : (_collaborationRequestString(req['location'])
                            .trim()
                            .isEmpty
                        ? '-'
                        : _collaborationRequestString(req['location']));
            final primaryCat = req == null
                ? '-'
                : _collaborationReqPrimaryCategoryDisplay(req);
            final detailCat = req == null
                ? '-'
                : _collaborationReqDetailServiceCategoriesLine(req);

            final appStatusRaw = _collaborationRequestString(app['status']);
            final appStatusLower = appStatusRaw.toLowerCase();
            final badgeStyle = collaborationMyApplicationBadgeStyle(app['status']);
            final statusLabel =
                collaborationMyApplicationStatusLabelKo(app['status']);

            final created =
                _firestoreAsDateTime(app['createdAt']) ??
                    _firestoreAsDateTime(app['updatedAt']);
            final createdStr = created == null
                ? '-'
                : '${created.year}.${created.month.toString().padLeft(2, '0')}.${created.day.toString().padLeft(2, '0')} '
                    '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

            String? footnote;
            if (appStatusLower.isEmpty || appStatusLower == 'pending') {
              footnote = '의뢰업체의 확인을 기다리는 중입니다.';
            } else if (appStatusLower == 'rejected') {
              footnote = '거절된 지원입니다.';
            } else if (appStatusLower == 'cancelled') {
              footnote = '취소한 지원입니다.';
            }

            return Material(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: req == null
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '공고가 삭제되었거나 접근할 수 없습니다.',
                            ),
                          ),
                        );
                      }
                    : () {
                        final ownerFs =
                            _collaborationRequestString(req['ownerUid']);
                        if (ownerFs.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('공고 정보를 찾을 수 없습니다.'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          PartnerRequestDetailScreen(
                            requestId: reqId,
                            ownerUid: ownerFs,
                            ownerEmailFromRequest: ownerEmailLine.isEmpty
                                ? null
                                : ownerEmailLine,
                          ),
                        ));
                      },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        titleReq,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      if (footnote != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          footnote,
                          style: textTheme.bodySmall?.copyWith(
                            height: 1.4,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '지역',
                        body: region,
                      ),
                      const SizedBox(height: 8),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '메인카테고리',
                        body: primaryCat,
                      ),
                      const SizedBox(height: 8),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '세부시공분야',
                        body: detailCat,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              '내 지원 상태',
                              style: textTheme.labelSmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: badgeStyle.background,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: badgeStyle.foreground,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '내가 제안한 금액',
                        body:
                            collaborationFormatProposedPrice(app['proposedPrice']),
                      ),
                      const SizedBox(height: 8),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '가능 일정',
                        body: _collaborationReqMissingStr(
                          app,
                          'availableSchedule',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _collaborationDetailLabeledBlock(
                        textTheme: textTheme,
                        label: '지원일',
                        body: createdStr,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (_loadingRequests)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}
