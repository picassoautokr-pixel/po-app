part of 'main.dart';

// ---------------------------------------------------------------------------
// 업체 대량 업로드 — CSV 업로드는 pio-data-tools(Python) 에서 처리합니다.
// file_picker 의존성을 제거하면서 앱 내 CSV 업로드 기능을 비활성화하고
// 관리자에게 안내 화면을 대신 표시합니다.
// ---------------------------------------------------------------------------

class BusinessBulkUploadScreen extends StatelessWidget {
  const BusinessBulkUploadScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('업체 대량 업로드'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_outlined,
                    size: 36,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'CSV 업로드는\n관리자 데이터툴에서 진행합니다',
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '업체 데이터 일괄 등록은\npio-data-tools(Python)를 통해 처리됩니다.\n\n'
                  '관리자에게 문의하거나 데이터툴을 직접 사용해 주세요.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('돌아가기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
