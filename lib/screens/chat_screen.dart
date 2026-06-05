part of '../main.dart';

/// Firestore 메시지 + Storage 이미지 첨부 1:1 채팅.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.requestId,
    required this.partnerUid,
    required this.requestTitle,
    this.partnerDisplayName,
    this.chatFirestoreDocId,
  });

  /// `collaborationRequests` 문서 ID.
  final String requestId;
  /// 대화 상대 `users/{partnerUid}`.
  final String partnerUid;
  final String requestTitle;
  final String? partnerDisplayName;
  /// `chats` 문서 ID. null이면 [requestId]_[partnerUid] 형식.
  final String? chatFirestoreDocId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _accent = Color(0xFF007AFF);
  /// flutter_image_compress (요구: quality 65, 최대 변 1600).
  static const int _chatImageCompressQuality = 65;
  static const int _chatImageMaxSide = 1600;
  static const int _chatMultiPickMax = 5;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 업로드 완료 전 로컬 미리보기 경로 (문서 id → 압축 파일 경로).
  final Map<String, String> _localPreviewPaths = <String, String>{};
  final Map<String, double> _uploadProgress = <String, double>{};

  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  bool _shareSelectedBusy = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _liveMsgDocs =
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  String? _editingMessageId;

  int _lastAppliedMessageLen = -1;

  String get _chatId {
    final custom = widget.chatFirestoreDocId?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return collaborationChatFirestoreId(widget.requestId, widget.partnerUid);
  }

  void _syncScrollForMessageCount(int n) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_lastAppliedMessageLen == n) return;
      _lastAppliedMessageLen = n;
      final extent = _scrollController.position.maxScrollExtent;
      if (extent <= 0) return;
      _scrollController.jumpTo(extent);
    });
  }

  String? _resolveImageLocalPath(String docId, Map<String, dynamic> data) {
    final mem = _localPreviewPaths[docId];
    if (mem != null && platformFileExists(mem)) return mem;
    final lp = data['localPath'];
    if (lp is String && lp.trim().isNotEmpty) {
      final path = lp.trim();
      if (platformFileExists(path)) return path;
    }
    return null;
  }

  double? _resolveUploadProgress(String docId, Map<String, dynamic> data) {
    final live = _uploadProgress[docId];
    if (live != null) return live;
    final pr = data['progress'];
    if (pr is num) return pr.toDouble().clamp(0.0, 1.0);
    return null;
  }

  void _openChatImageFullscreen({
    required String? networkUrl,
    required String? localPath,
  }) {
    final u = networkUrl?.trim() ?? '';
    var lp = localPath?.trim() ?? '';
    if (lp.isNotEmpty && !platformFileExists(lp)) lp = '';
    if (u.isEmpty && lp.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _ChatFullScreenImageView(
          imageUrl: u.isNotEmpty ? u : null,
          localFilePath: lp.isNotEmpty ? lp : null,
        ),
      ),
    );
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLiveDoc(String docId) {
    for (final d in _liveMsgDocs) {
      if (d.id == docId) return d;
    }
    return null;
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(String docId) {
    setState(() {
      if (_selectedMessageIds.contains(docId)) {
        _selectedMessageIds.remove(docId);
        if (_selectedMessageIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedMessageIds.add(docId);
      }
    });
  }

  void _openImageGalleryIfComplete(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    String tappedDocId,
  ) {
    final urls = _poChatGalleryImageUrls(allDocs);
    if (urls.isEmpty) return;
    final start =
        _poChatGalleryStartIndex(allDocs, tappedDocId).clamp(0, urls.length - 1);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => ImageGalleryScreen(
          imageUrls: urls,
          initialIndex: start,
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _selectedDocsOrdered() {
    final sel = _selectedMessageIds;
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in _liveMsgDocs) {
      if (sel.contains(d.id)) out.add(d);
    }
    return out;
  }

  Future<void> _copySelectedMessages() async {
    final parts = <String>[];
    for (final d in _selectedDocsOrdered()) {
      final m = d.data();
      if (_poChatMessageIsDeleted(m)) continue;
      if ((m['type'] as String?)?.trim() != 'text') continue;
      final t = (m['text'] as String?)?.trim() ?? '';
      if (t.isEmpty || t == '삭제된 메시지입니다.') continue;
      parts.add(t);
    }
    if (parts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복사할 텍스트가 없습니다.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사했습니다.')),
    );
  }

  Future<void> _runWithShareLoading(Future<void> Function() task) async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
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
    try {
      await task();
    } finally {
      if (mounted) nav.pop();
    }
  }

  Future<XFile?> _downloadChatImageToTempFile(String imageUrl, int serial) async {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // 플랫폼 분기: 모바일은 임시 파일 저장, 웹은 null 반환
    return platformDownloadImageToTemp(imageUrl, serial);
  }

  Future<void> _shareSelectedMessages() async {
    if (_shareSelectedBusy) return;

    final textParts = <String>[];
    final imageUrls = <String>[];
    for (final d in _selectedDocsOrdered()) {
      final m = d.data();
      if (_poChatMessageIsDeleted(m)) continue;
      final ty = (m['type'] as String?)?.trim() ?? '';
      if (ty == 'text') {
        final t = (m['text'] as String?)?.trim() ?? '';
        if (t.isEmpty || t == '삭제된 메시지입니다.') continue;
        textParts.add(t);
      } else if (ty == 'image') {
        final u = (m['imageUrl'] as String?)?.trim() ?? '';
        if (u.isNotEmpty) imageUrls.add(u);
      }
    }

    final combinedText = textParts.join('\n');
    if (combinedText.isEmpty && imageUrls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 내용이 없습니다.')),
      );
      return;
    }

    final hasText = combinedText.isNotEmpty;
    final hasImageUrls = imageUrls.isNotEmpty;

    if (hasText && hasImageUrls) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            content: const Text(
              '카카오톡은 사진과 텍스트를 동시에 공유할 때 텍스트가 누락될 수 있습니다. 텍스트를 클립보드에 복사한 뒤 사진을 공유합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('공유'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    if (!mounted) return;
    setState(() {
      _shareSelectedBusy = true;
    });

    Future<void> invokeShare(List<XFile> files, bool anyImageFailed) async {
      if (!mounted) return;

      if (files.isEmpty && combinedText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              anyImageFailed && imageUrls.isNotEmpty
                  ? '일부 이미지를 공유하지 못했습니다.'
                  : '공유할 내용이 없습니다.',
            ),
          ),
        );
        return;
      }

      if (anyImageFailed && imageUrls.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일부 이미지를 공유하지 못했습니다.')),
        );
      }

      final hasText = combinedText.isNotEmpty;
      final hasFiles = files.isNotEmpty;

      try {
        if (!hasText && hasFiles) {
          // ignore: deprecated_member_use
          await platformShareXFiles(files);
        } else if (hasText && !hasFiles) {
          // ignore: deprecated_member_use
          await platformShareText(combinedText);
        } else if (hasText && hasFiles) {
          await Clipboard.setData(ClipboardData(text: combinedText));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '텍스트가 복사되었습니다. 사진 전송 후 채팅창에 붙여넣기 해주세요.',
              ),
            ),
          );
          // ignore: deprecated_member_use
          await platformShareXFiles(files);
        }
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공유에 실패했습니다.')),
        );
      }
    }

    try {
      if (imageUrls.isEmpty) {
        await invokeShare(const <XFile>[], false);
        return;
      }

      await _runWithShareLoading(() async {
        final files = <XFile>[];
        var anyImageFailed = false;
        for (var i = 0; i < imageUrls.length; i++) {
          final xf = await _downloadChatImageToTempFile(imageUrls[i], i);
          if (xf != null) {
            files.add(xf);
          } else {
            anyImageFailed = true;
          }
        }
        await invokeShare(files, anyImageFailed);
      });
    } finally {
      if (mounted) {
        setState(() {
          _shareSelectedBusy = false;
          _selectionMode = false;
          _selectedMessageIds.clear();
        });
      }
    }
  }

  Future<void> _shareOneMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data();
    if (_poChatMessageIsDeleted(m)) return;
    final ty = (m['type'] as String?)?.trim() ?? '';
    if (ty == 'text') {
      final t = (m['text'] as String?)?.trim() ?? '';
      if (t.isEmpty) return;
      await platformShareText(t);
    } else if (ty == 'image') {
      final u = (m['imageUrl'] as String?)?.trim() ?? '';
      if (u.isEmpty) return;
      Future<void> shareImage() async {
        final xf = await _downloadChatImageToTempFile(u, 0);
        if (!mounted) return;
        if (xf == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('일부 이미지를 공유하지 못했습니다.')),
          );
          return;
        }
        await platformShareXFiles([xf]);
      }

      await _runWithShareLoading(shareImage);
    }
  }

  Future<void> _softDeleteMessageDoc(String docId) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(docId)
        .update(<String, Object?>{
          'isDeleted': true,
          'text': '삭제된 메시지입니다.',
          'imageUrl': '',
          'thumbnailUrl': '',
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _deleteSelectedMessages() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    var deleted = 0;
    for (final d in _selectedDocsOrdered()) {
      if (!_documentIsMine(d.data(), me)) continue;
      if (_poChatMessageIsDeleted(d.data())) continue;
      try {
        await _softDeleteMessageDoc(d.id);
        deleted++;
      } on Object catch (_) {}
    }
    if (!mounted) return;
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0 ? '메시지를 삭제했습니다.' : '삭제할 내 메시지가 없습니다.',
        ),
      ),
    );
  }

  bool _canEditSingleSelectedText() {
    if (_selectedMessageIds.length != 1) return false;
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final id = _selectedMessageIds.first;
    final doc = _findLiveDoc(id);
    if (doc == null) return false;
    final m = doc.data();
    if (_poChatMessageIsDeleted(m)) return false;
    if (!_documentIsMine(m, me)) return false;
    return (m['type'] as String?)?.trim() == 'text';
  }

  void _startEditSingleSelectedText() {
    final id = _selectedMessageIds.first;
    final doc = _findLiveDoc(id);
    if (doc == null) return;
    final t = (doc.data()['text'] as String?) ?? '';
    setState(() {
      _editingMessageId = id;
      _inputController.text = t;
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _cancelTextEdit() {
    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });
  }

  Future<void> _copyOneTextMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data();
    final t = (m['text'] as String?)?.trim() ?? '';
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('복사했습니다.')),
    );
  }

  Future<void> _editTextMessageDialog(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!_documentIsMine(doc.data(), me)) return;
    final cur = (doc.data()['text'] as String?) ?? '';
    final controller = TextEditingController(text: cur);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('메시지 수정'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '내용'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      controller.dispose();
      return;
    }
    final next = controller.text.trim();
    controller.dispose();
    if (next.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(doc.id)
          .update(<String, Object?>{
            'text': next,
            'isEdited': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정하지 못했습니다: $e')),
      );
    }
  }

  Future<void> _confirmDeleteOne(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!_documentIsMine(doc.data(), me)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메시지 삭제'),
        content: const Text('이 메시지를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _softDeleteMessageDoc(doc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지를 삭제했습니다.')),
        );
      }
    }
  }

  Future<void> _onMessageLongPress(String docId) async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final doc = _findLiveDoc(docId);
    if (doc == null) return;
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.add(docId);
    });

    final data = doc.data();
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMine = _documentIsMine(data, me);
    final isDel = _poChatMessageIsDeleted(data);
    final ty = (data['type'] as String?)?.trim() ?? '';

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomPad =
            poBottomSheetContentBottomPadding(ctx, extra: 40);
        return SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPad),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '메시지',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!isDel && ty == 'text') ...[
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('복사'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_copyOneTextMessage(doc));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('공유'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_shareOneMessage(doc));
                  },
                ),
                if (isMine)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('수정'),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_editTextMessageDialog(doc));
                    },
                  ),
              ],
              if (!isDel && ty == 'image') ...[
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('공유'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_shareOneMessage(doc));
                  },
                ),
                if (isMine &&
                    _normalizedImageStatus(
                          data,
                          (data['imageUrl'] as String?)?.trim() ?? '',
                          _resolveImageLocalPath(doc.id, data),
                        ) ==
                        'failed')
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('다시 보내기'),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_retryImageUpload(doc.id));
                    },
                  ),
              ],
              if (isMine && !isDel)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                  title: Text('삭제', style: TextStyle(color: Colors.red.shade700)),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_confirmDeleteOne(doc));
                  },
                ),
              const SizedBox(height: 8),
            ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildChatAppBar({
    required TextTheme textTheme,
    required String titlePrimary,
    required String? partnerLabel,
  }) {
    if (_selectionMode) {
      return AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectionMode,
          tooltip: '취소',
        ),
        title: Text(
          '${_selectedMessageIds.length}개 선택',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '복사',
            onPressed: _copySelectedMessages,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: '공유',
            onPressed: _shareSelectedBusy ? null : _shareSelectedMessages,
            icon: const Icon(Icons.share_rounded),
          ),
          if (_canEditSingleSelectedText())
            IconButton(
              tooltip: '수정',
              onPressed: _startEditSingleSelectedText,
              icon: const Icon(Icons.edit_rounded),
            ),
          IconButton(
            tooltip: '삭제',
            onPressed: _deleteSelectedMessages,
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.black87,
      toolbarHeight:
          partnerLabel != null && partnerLabel.isNotEmpty ? 68 : null,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            titlePrimary,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (partnerLabel != null && partnerLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              partnerLabel,
              style: textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: () {
            runWithBriefLoading(context, () {
              if (!context.mounted) return;
              Navigator.of(context).push(poSmoothPushRoute<void>(
                CollaborationCompleteScreen(
                  requestTitle: widget.requestTitle,
                ),
              ));
            });
          },
          child: Text(
            '작업 완료',
            style: textTheme.labelLarge?.copyWith(
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _normalizedImageStatus(
    Map<String, dynamic> data,
    String url,
    String? localPath,
  ) {
    final r = data['status'];
    if (r is String && r.trim().isNotEmpty) return r.trim();
    if (url.isNotEmpty) return 'complete';
    if (localPath != null) return 'uploading';
    return 'failed';
  }

  /// 이미지 압축: 모바일은 FlutterImageCompress, 웹은 원본 바이트 사용.
  /// 반환값: 모바일=File?, 웹=null (웹에서는 XFile 바이트 직접 업로드)
  Future<dynamic> _compressChatImage(XFile xFile) async {
    return platformCompressImage(
      xFile,
      quality: _chatImageCompressQuality,
      maxSide: _chatImageMaxSide,
    );
  }

  void _disposeLocalPreviewFile(String docId) {
    final path = _localPreviewPaths.remove(docId);
    _uploadProgress.remove(docId);
    if (path != null) {
      platformDeleteFile(path);
    }
  }

  Future<void> _executeUploadForMessage({
    required String docId,
    required XFile xFile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final storagePath = 'chat_images/$_chatId/$docId.jpg';
    final ref = FirebaseStorage.instance.ref(storagePath);
    // 플랫폼 분기: 웹=putData(bytes), 모바일=putFile(File)
    final bytes = await xFile.readAsBytes();
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(docId);

    var lastProgressBucket = -1;
    StreamSubscription<TaskSnapshot>? sub;
    sub = task.snapshotEvents.listen((snap) {
      final total = snap.totalBytes;
      if (total <= 0) return;
      final p = (snap.bytesTransferred / total).clamp(0.0, 1.0);
      if (mounted) {
        setState(() => _uploadProgress[docId] = p);
      }
      final bucket = (p * 4).floor().clamp(0, 4);
      if (bucket > lastProgressBucket) {
        lastProgressBucket = bucket;
        unawaited(
          msgRef.update(<String, Object?>{
            'progress': p,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        );
      }
    });

    try {
      await task;
      final imageUrl = await ref.getDownloadURL();
      await msgRef.update(<String, Object?>{
        'imageUrl': imageUrl,
        'thumbnailUrl': imageUrl,
        'localPath': '',
        'status': 'complete',
        'progress': 1.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _uploadProgress.remove(docId);
          _disposeLocalPreviewFile(docId);
        });
      } else {
        _disposeLocalPreviewFile(docId);
      }
      await _notifyChatRoomSummaryOutbound('사진');
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        unawaited(collaborationApplyOutgoingUnreadCounts(
          chatId: _chatId,
          myUid: u.uid,
          partnerUid: widget.partnerUid,
        ));
      }
    } on Object catch (e) {
      try {
        await msgRef.update(<String, Object?>{
          'status': 'failed',
          'progress': 0.0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on Object catch (_) {}
      if (mounted) {
        setState(() => _uploadProgress.remove(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 전송 실패: $e')),
        );
      }
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _handleOneImageUpload(XFile xFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 모바일: 압축된 File 반환, 웹: null 반환 (원본 바이트 사용)
    final compressedFile = await _compressChatImage(xFile);
    // 업로드에 사용할 XFile 결정
    final uploadXFile = (compressedFile != null && !kIsWeb)
        ? XFile((compressedFile as dynamic).path as String)
        : xFile;

    if (!mounted) return;
    final col = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages');
    final docRef = col.doc();
    final id = docRef.id;

    await docRef.set(<String, Object?>{
      'messageId': id,
      'senderUid': user.uid,
      'senderEmail': user.email ?? '',
      'type': 'image',
      'text': '',
      'imageUrl': '',
      'thumbnailUrl': '',
      'localPath': kIsWeb ? '' : uploadXFile.path,
      'status': 'uploading',
      'progress': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      _localPreviewPaths[id] = kIsWeb ? '' : uploadXFile.path;
      _uploadProgress[id] = 0.0;
    });

    await _executeUploadForMessage(docId: id, xFile: uploadXFile);
  }

  Future<void> _pickAndUploadGalleryImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final picker = ImagePicker();
    final List<XFile> pickedRaw;
    try {
      pickedRaw = await picker.pickMultiImage(imageQuality: 85);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진을 선택하지 못했습니다: $e')),
      );
      return;
    }

    final picked = pickedRaw.length > _chatMultiPickMax
        ? pickedRaw.sublist(0, _chatMultiPickMax)
        : pickedRaw;
    if (pickedRaw.length > _chatMultiPickMax && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '한 번에 최대 $_chatMultiPickMax장까지 전송합니다. '
            '처음 $_chatMultiPickMax장만 선택되었습니다.',
          ),
        ),
      );
    }

    if (picked.isEmpty || !mounted) return;
    unawaited(Future.wait(picked.map(_handleOneImageUpload)));
  }

  Future<void> _retryImageUpload(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final path = _localPreviewPaths[docId];
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('다시 보내려면 사진을 새로 선택해 주세요.'),
        ),
      );
      return;
    }
    if (!platformFileExists(path)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('파일을 찾을 수 없어 재시도할 수 없습니다.'),
        ),
      );
      return;
    }
    final f = XFile(path);

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(docId)
          .update(<String, Object?>{
            'status': 'uploading',
            'imageUrl': '',
            'thumbnailUrl': '',
            'progress': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('재시도 준비 실패: $e')),
      );
      return;
    }

    if (mounted) {
      setState(() => _uploadProgress[docId] = 0.0);
    }
    unawaited(_executeUploadForMessage(docId: docId, xFile: f));
  }

  Future<void> _sendText() async {
    final trimmed = _inputController.text.trim();
    if (trimmed.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final editId = _editingMessageId?.trim();
    if (editId != null && editId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .doc(editId)
            .update(<String, Object?>{
              'text': trimmed,
              'isEdited': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        if (mounted) {
          setState(() {
            _editingMessageId = null;
            _inputController.clear();
          });
        }
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정하지 못했습니다: $e')),
        );
      }
      return;
    }

    try {
      _inputController.clear();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add(<String, Object?>{
            'senderUid': user.uid,
            'senderEmail': user.email ?? '',
            'type': 'text',
            'text': trimmed,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await _notifyChatRoomSummaryOutbound(trimmed);
      unawaited(collaborationApplyOutgoingUnreadCounts(
        chatId: _chatId,
        myUid: user.uid,
        partnerUid: widget.partnerUid,
      ));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전송하지 못했습니다: $e')),
      );
    }
  }

  bool _documentIsMine(Map<String, dynamic> data, String myUid) {
    final uid = data['senderUid'];
    return uid is String && uid == myUid;
  }

  Widget _wrapMessageBubble({
    required String docId,
    required Widget child,
    VoidCallback? onTap,
    bool allowLongPress = true,
  }) {
    final selected = _selectedMessageIds.contains(docId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? _accent.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            onLongPress: allowLongPress
                ? () => unawaited(_onMessageLongPress(docId))
                : null,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _bubbleShell({
    required bool isMine,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment:
            isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageTile(
    QueryDocumentSnapshot<Map<String, dynamic>> docSnap,
    String myUid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final data = docSnap.data();
    final docId = docSnap.id;
    final textTheme = Theme.of(context).textTheme;
    final isMine = _documentIsMine(data, myUid);

    if (_poChatMessageIsDeleted(data)) {
      return _wrapMessageBubble(
        docId: docId,
        allowLongPress: false,
        onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
        child: _bubbleShell(
          isMine: isMine,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                '삭제된 메시지입니다.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final typeRaw = data['type'];
    final parsedType = typeRaw is String ? typeRaw.trim() : '';

    if (parsedType == 'image') {
      final rawUrl = data['imageUrl'];
      final url = rawUrl is String ? rawUrl.trim() : '';
      final resolvedLocal = _resolveImageLocalPath(docId, data);
      final status = _normalizedImageStatus(data, url, resolvedLocal);
      final progress = _resolveUploadProgress(docId, data);

      if (status == 'failed') {
        return _wrapMessageBubble(
          docId: docId,
          onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
          child: _bubbleShell(
            isMine: isMine,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isMine
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMine ? _accent : Colors.grey.shade300,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: Colors.red.shade700, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '사진을 보내지 못했습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isMine) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () => _retryImageUpload(docId),
                          child: const Text('재시도'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final borderClr =
          isMine ? _accent.withValues(alpha: 0.55) : Colors.grey.shade300;
      final hasLocal = resolvedLocal != null &&
          resolvedLocal.isNotEmpty &&
          platformFileExists(resolvedLocal);

      Widget imageChild;
      if (url.isNotEmpty && status == 'complete') {
        imageChild = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, _) => SizedBox(
            height: 180,
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '이미지 표시 불가',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),
        );
      } else if (hasLocal) {
        imageChild = kIsWeb
            ? const Center(child: CircularProgressIndicator())
            : _buildLocalImageWidget(resolvedLocal!, textTheme);
      } else {
        imageChild = ColoredBox(
          color: Colors.grey.shade200,
          child: SizedBox(
            height: 160,
            child: Center(
              child: Icon(Icons.image_outlined,
                  size: 48, color: Colors.grey.shade500),
            ),
          ),
        );
      }

      final showUploadOverlay =
          status == 'uploading' || (url.isEmpty && hasLocal);

      final canGallery = url.isNotEmpty && status == 'complete';

      return _wrapMessageBubble(
        docId: docId,
        onTap: () {
          if (_selectionMode) {
            _toggleMessageSelection(docId);
            return;
          }
          if (canGallery) {
            _openImageGalleryIfComplete(allDocs, docId);
          } else if (hasLocal) {
            _openChatImageFullscreen(
              networkUrl: url.isNotEmpty ? url : null,
              localPath: resolvedLocal,
            );
          }
        },
        child: _bubbleShell(
          isMine: isMine,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: borderClr, width: 1.2),
                ),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 280),
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: imageChild,
                      ),
                      if (showUploadOverlay)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.2,
                                  color: Colors.white,
                                  value: (progress != null &&
                                          progress > 0 &&
                                          progress < 1)
                                      ? progress
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final textRaw = data['text'];
    final text =
        textRaw is String ? textRaw.trim() : '';
    if (text.isEmpty) return const SizedBox.shrink();

    final bg = isMine ? _accent : Colors.white;
    final fg = isMine ? Colors.white : Colors.black87;
    final isEdited = data['isEdited'] == true;

    return _wrapMessageBubble(
      docId: docId,
      onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
      child: _bubbleShell(
        isMine: isMine,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            border: isMine
                ? null
                : Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdited)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '편집됨',
                      style: textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bootstrapChatRoomDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await collaborationEnsureChatRoomShell(
      chatId: _chatId,
      myUid: user.uid,
      partnerUid: widget.partnerUid,
      requestId: widget.requestId,
      requestTitle: widget.requestTitle,
    );
  }

  Future<void> _notifyChatRoomSummaryOutbound(String preview) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final pruned =
        preview.length > 200 ? preview.substring(0, 200) : preview;
    await collaborationTouchChatRoomSummary(
      chatId: _chatId,
      myUid: user.uid,
      partnerUid: widget.partnerUid,
      requestId: widget.requestId,
      requestTitle: widget.requestTitle,
      lastMessagePreview: pruned,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _bootstrapChatRoomDocument();
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await collaborationResetUnreadForUserInChat(
          chatId: _chatId,
          userUid: u.uid,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final partnerLabel =
        widget.partnerDisplayName?.trim();

    final titlePrimary = widget.requestTitle.trim().isEmpty
        ? '채팅'
        : widget.requestTitle.trim();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildChatAppBar(
        textTheme: textTheme,
        titlePrimary: titlePrimary,
        partnerLabel: partnerLabel,
      ),
      body: SafeArea(
        top: false,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_chatId)
                    .collection('messages')
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    poReportFirestoreSnapshotError(
                      'chat_messages',
                      snapshot.error!,
                    );
                    return Center(
                      child: poFirestoreUserErrorPlaceholder(
                        context,
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    );
                  }
                  if (snapshot.connectionState ==
                          ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final msgDocs = snapshot.data?.docs ?? [];
                  _liveMsgDocs = msgDocs;
                  _syncScrollForMessageCount(msgDocs.length);

                  if (msgDocs.isEmpty) {
                    return Center(
                      child: Text(
                        '메시지를 보내 대화를 시작해 보세요.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      poBottomSheetContentBottomPadding(context, extra: 36),
                    ),
                    itemCount: msgDocs.length,
                    itemBuilder: (context, index) {
                      return _buildMessageTile(
                        msgDocs[index],
                        myUid,
                        msgDocs,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Material(
            color: Colors.white,
            elevation: 8,
            shadowColor: Colors.black26,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editingMessageId != null)
                    Material(
                      color: _accent.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.edit_note_rounded,
                                size: 22, color: _accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '메시지 수정 중',
                                style: textTheme.labelLarge?.copyWith(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _cancelTextEdit,
                              child: const Text('취소'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '갤러리에서 사진',
                      onPressed: () => unawaited(_pickAndUploadGalleryImages()),
                      icon: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.grey.shade700,
                      ),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: '메시지 입력',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sendText,
                      style: IconButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 22),
                    ),
                  ],
                ),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// 모바일 전용: 로컬 파일을 Image.file로 표시.
  /// 웹에서는 이 함수가 호출되지 않습니다 (kIsWeb 분기로 보호됨).
  Widget _buildLocalImageWidget(String path, TextTheme textTheme) {
    // ignore: avoid_dynamic_calls
    return Image.file(
      // dart:io는 모바일에서만 사용되므로 platform_io.dart에서 처리
      platformBuildFile(path),
      fit: BoxFit.cover,
      errorBuilder: (context, err, st) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '미리보기를 불러올 수 없습니다',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}

Future<void> toggleFavoriteCollaborationRequestForMe(
  BuildContext context,
  String requestId,
) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final rid = requestId.trim();
  if (me == null || rid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }

  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(me);
    final snap = await ref.get();
    final raw = snap.data()?['favoriteRequestIds'];
    final favList = <String>[
      if (raw is Iterable)
        for (final e in raw)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final has = favList.contains(rid);

    await ref.set(
      <String, Object?>{
        'favoriteRequestIds':
            has ? FieldValue.arrayRemove([rid]) : FieldValue.arrayUnion([rid]),
      },
      SetOptions(merge: true),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(has ? '공고 즐겨찾기를 해제했습니다.' : '공고를 즐겨찾기에 추가했습니다.'),
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('처리하지 못했습니다: $e')),
    );
  }
}

Future<void> toggleFavoritePartnerUidForMe(
    BuildContext context,
    String partnerUid,) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final pid = partnerUid.trim();
  if (me == null || pid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }

  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(me);
    final snap = await ref.get();
    final raw = snap.data()?['favoritePartnerUids'];
    final favList = <String>[
      if (raw is Iterable)
        for (final e in raw)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final has = favList.contains(pid);

    await ref.set(
      <String, Object?>{
        'favoritePartnerUids':
            has ? FieldValue.arrayRemove([pid]) : FieldValue.arrayUnion([pid]),
      },
      SetOptions(merge: true),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(has ? '즐겨찾기를 해제했습니다.' : '즐겨찾기에 추가했습니다.'),
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('처리하지 못했습니다: $e')),
    );
  }
}
