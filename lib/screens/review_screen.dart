part of '../main.dart';

/// 협업 만족도 평가
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.requestTitle});

  final String requestTitle;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const Color _accent = Color(0xFF007AFF);

  static const List<String> _ratingLabels = [
    '시공 마감',
    '시공 속도',
    'A/S',
    '응답 속도',
    '친절함',
    '가성비',
  ];

  late final List<int> _scores;
  final TextEditingController _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scores = List<int>.filled(_ratingLabels.length, 5);
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _submit() {
    runWithBriefLoading(context, () {
      final parts = <String>[
        '글: ${widget.requestTitle}',
        for (var i = 0; i < _ratingLabels.length; i++)
          '${_ratingLabels[i]}: ${_scores[i]}점',
        '메모: ${_memoController.text}',
      ];
      // ignore: avoid_print
      print(parts.join('\n'));
      if (!mounted) return;
      _goHome(context);
    });
  }

  @override
  void dispose() {
    _memoController.dispose();
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
                  const SizedBox(height: 20),
                  for (var i = 0; i < _ratingLabels.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _ReviewRatingRow(
                      label: _ratingLabels[i],
                      score: _scores[i],
                      accent: _accent,
                      onChanged: (v) {
                        setState(() => _scores[i] = v.round());
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _memoController,
                    maxLines: 4,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: '간단 후기',
                      hintText: '시공 속도나 소통 같은 점 적어 주세요',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade500, fontSize: 14),
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
                        borderSide:
                            const BorderSide(color: _accent, width: 1.5),
                      ),
                    ),
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
                onPressed: _submit,
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
                child: const Text('평가 등록'),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ReviewRatingRow extends StatelessWidget {
  const _ReviewRatingRow({
    required this.label,
    required this.score,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final int score;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '$score',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  ' / 10',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                inactiveTrackColor: Colors.grey.shade300,
                thumbColor: accent,
                trackHeight: 3.5,
              ),
              child: Slider(
                value: score.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$score',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
