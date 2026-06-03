part of '../main.dart';

/// 채팅 이미지 연속 보기 (PageView).
class ImageGalleryScreen extends StatefulWidget {
  const ImageGalleryScreen({
    super.key,
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final last = widget.imageUrls.length - 1;
    final initial = widget.initialIndex.clamp(0, last < 0 ? 0 : last);
    _currentIndex = initial;
    _pageController = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.imageUrls.length;
    if (n == 0) {
      return const Scaffold(
        body: Center(child: Text('이미지가 없습니다.')),
      );
    }
    final label = '${_currentIndex + 1} / $n';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: n,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) {
          final u = widget.imageUrls[i];
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.contain,
                placeholder: (context, _) => const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
                errorWidget: (context, url, error) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '이미지를 불러올 수 없습니다.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 채팅 말풍선에서 로컬 미리보기만 단일 전체화면.
class _ChatFullScreenImageView extends StatelessWidget {
  const _ChatFullScreenImageView({
    this.imageUrl,
    this.localFilePath,
  });

  final String? imageUrl;
  final String? localFilePath;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final path = localFilePath?.trim() ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: url.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (ctx, _) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '이미지를 불러올 수 없습니다.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : path.isNotEmpty
                  ? Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        '파일을 열 수 없습니다.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : const Text(
                      '표시할 이미지가 없습니다.',
                      style: TextStyle(color: Colors.white70),
                    ),
        ),
      ),
    );
  }
}
