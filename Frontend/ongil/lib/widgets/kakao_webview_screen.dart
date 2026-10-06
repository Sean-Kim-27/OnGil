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
          // kakaomap://, intent://, market:// 등 앱 실행용 스킴은 웹뷰가 처리할 수 없어
          // ERR_UNKNOWN_URL_SCHEME 오류 페이지가 노출된다. http/https만 통과시킨다.
          onNavigationRequest: (request) {
            final scheme = Uri.tryParse(request.url)?.scheme ?? '';
            if (scheme != 'http' && scheme != 'https') {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
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

/// 장소의 카카오맵 상세 페이지를 찾아 앱 내부 웹뷰로 열어줌.
/// 좌표가 없거나 상세 페이지가 없으면 검색 안내로 대체함.
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
      title: const Text('상세 정보가 없는 장소예요', style: AppTextStyles.screenTitle),
      content: Text(
        "'$title'은(는) 연결된 상세 페이지가 없어요. 목록에 표시된 주소와 일정 정보로 확인해주세요.",
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            '확인',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
