import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../services/place_service.dart';
import 'app_top_bar.dart';

/// 카카오맵 상세 페이지(또는 검색 결과)를 앱 내부 웹뷰로 띄우는 화면.
class KakaoWebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const KakaoWebViewScreen({super.key, required this.title, required this.url});

  @override
  State<KakaoWebViewScreen> createState() => _KakaoWebViewScreenState();
}

class _KakaoWebViewScreenState extends State<KakaoWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _hasError = false;
          }),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (_) => setState(() {
            _isLoading = false;
            _hasError = true;
          }),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppBackTopBar(title: widget.title),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  if (_hasError && !_isLoading)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded, size: 36, color: AppColors.textSecondary),
                            const SizedBox(height: 10),
                            const Text(
                              '페이지를 불러오지 못했어요',
                              style: AppTextStyles.body,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => _controller.reload(),
                              child: const Text(
                                '다시 시도',
                                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 장소의 카카오맵 상세 페이지를 찾아서 앱 내부 웹뷰로 열어줌.
/// - 위경도가 없으면(백엔드 응답에 좌표가 안 실려온 경우) API를 부를 수 없으니 바로
///   "카카오맵에서 검색해보라"는 안내로 보냄.
/// - 카카오맵 자체에 상세 페이지가 없는 장소(404, 숙박·축제에서 흔함)도 같은 안내로 처리.
/// - 그 외 에러는 스낵바로만 짧게 알림.
Future<void> openKakaoPlaceDetail(
  BuildContext context, {
  required String title,
  double? latitude,
  double? longitude,
}) async {
  if (latitude == null || longitude == null) {
    await _showKakaoNotFoundDialog(context, title);
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(color: AppColors.accent),
    ),
  );

  try {
    final url = await PlaceService.instance.fetchKakaoDetailUrl(
      title: title,
      latitude: latitude,
      longitude: longitude,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 로딩 팝업 닫기
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => KakaoWebViewScreen(title: title, url: url)),
    );
  } on KakaoDetailUrlException catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (e.notFound) {
      await _showKakaoNotFoundDialog(context, title);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('상세 페이지를 불러오지 못했어요. 잠시 후 다시 시도해주세요.')),
    );
  }
}

Future<void> _showKakaoNotFoundDialog(BuildContext context, String title) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
      title: const Text('카카오맵에 없는 장소예요', style: AppTextStyles.screenTitle),
      content: Text(
        "'$title'은(는) 카카오맵에서 상세 페이지를 찾을 수 없어요. 카카오맵에서 직접 검색해보시겠어요?",
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => KakaoWebViewScreen(
                  title: '카카오맵 검색',
                  url: 'https://map.kakao.com/?q=${Uri.encodeComponent(title)}',
                ),
              ),
            );
          },
          child: const Text(
            '카카오맵에서 검색',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
