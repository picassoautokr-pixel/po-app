part of '../main.dart';

/// 작업 완료 후 비고·사진 등록
class CollaborationCompleteScreen extends StatefulWidget {
  const CollaborationCompleteScreen({super.key, required this.requestTitle});

  final String requestTitle;

  @override
  State<CollaborationCompleteScreen> createState() =>
      _CollaborationCompleteScreenState();
}

class _CollaborationCompleteScreenState
    extends State<CollaborationCompleteScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _reasonController = TextEditingController();
  bool _requestConfirmationToParty = false;

  InputDecoration _reasonFieldDecoration() {
    return InputDecoration(
      labelText: '현장·마감 비고 (선택)',
      hintText: '예: 기존도장 손상으로 등록 기준보다 들뜸이 조금 더 보입니다.',
      hintMaxLines: 6,
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
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
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

  void _onSave() {
    runWithBriefLoading(context, () {
      // ignore: avoid_print
      print(
        '글: ${widget.requestTitle}\n'
        '현장·마감 비고: ${_reasonController.text}\n'
        '상대 업체 확인 요청: ${_requestConfirmationToParty ? '예' : '아니오'}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(poSmoothPushRoute<void>(
        ReviewScreen(requestTitle: widget.requestTitle),
      ));
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
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
          '작업 완료',
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
                4,
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
                    widget.requestTitle,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '작업 마친 뒤, 완료 사진이나 현장 상황을 남겨 두면 분쟁 줄이기에 좋아요.',
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: _accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '꼭 쓸 필요 없고, 필요할 때 참고 자료로 쓰실 수 있습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                height: 1.5,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  CustomPaint(
                    painter: _DashedRoundRectPainter(
                      color: Colors.grey.shade400,
                      strokeWidth: 1.8,
                      radius: 14,
                    ),
                    child: SizedBox(
                      height: 156,
                      width: double.infinity,
                      child: Material(
                        color: Colors.grey.shade50,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: InkWell(
                          onTap: () {
                            runWithBriefLoading(context, () {
                              // ignore: avoid_print
                              print('완료 사진 첨부');
                            });
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 40, color: Colors.grey.shade500),
                              const SizedBox(height: 10),
                              Text(
                                '완료 사진 넣기',
                                style: textTheme.titleSmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _reasonController,
                    maxLines: 5,
                    minLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: _reasonFieldDecoration(),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _requestConfirmationToParty,
                    onChanged: (v) {
                      setState(() {
                        _requestConfirmationToParty = v ?? false;
                      });
                    },
                    title: Text(
                      '상대 업체에 확인 받기',
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    activeColor: _accent,
                    checkColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
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
                onPressed: _onSave,
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
                child: const Text('평가로 이동'),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
