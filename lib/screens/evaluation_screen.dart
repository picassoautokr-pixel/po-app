part of '../main.dart';

/// 협업 완료 후 파트너 평가.
class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({
    super.key,
    required this.requestId,
    required this.targetUid,
  });

  final String requestId;
  final String targetUid;

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late final Map<String, double> _scores = <String, double>{
    for (final String k in collaborationReviewScoreKeys) k: 8,
  };

  final TextEditingController _commentCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final target = widget.targetUid.trim();
    final rid = widget.requestId.trim();
    if (target.isEmpty || rid.isEmpty) return;

    final docId = collaborationReviewDocId(user.uid, rid);
    if (docId.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(target)
          .collection('reviews')
          .doc(docId);

      final existing = await docRef.get();
      final scoresMap = <String, int>{
        for (final String k in collaborationReviewScoreKeys)
          k: (_scores[k] ?? 8).round().clamp(1, 10),
      };

      final payload = <String, Object?>{
        'reviewerUid': user.uid,
        'requestId': rid,
        'scores': scoresMap,
        'comment': _commentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(payload, SetOptions(merge: true));
      await collaborationRecomputeUserAverageRating(target);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('평가가 완료되었습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('평가 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _sliderRow(TextTheme textTheme, String key) {
    final label =
        collaborationReviewScoreLabelsKo[key] ?? key;
    final v = (_scores[key] ?? 8).clamp(1.0, 10.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${v.round()}',
              style: textTheme.titleSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: v,
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: _accent,
          onChanged: _submitting
              ? null
              : (double nv) => setState(() => _scores[key] = nv),
        ),
        const SizedBox(height: 8),
      ],
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
          '협업 평가',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          poFullScreenScrollBottomPadding(context),
        ),
        children: [
          Text(
            '항목별 1~10점을 선택한 뒤, 총평을 남겨 주세요.',
            style: textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final String k in collaborationReviewScoreKeys)
            _sliderRow(textTheme, k),
          Text(
            '총평',
            style: textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            minLines: 4,
            maxLines: 10,
            enabled: !_submitting,
            decoration: InputDecoration(
              hintText: '협업 경험을 간단히 적어 주세요',
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_submitting ? '저장 중…' : '평가 제출'),
          ),
        ],
      ),
      ),
    );
  }
}
