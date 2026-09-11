import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/brand_marks.dart';
import 'signup_screen.dart';
import 'terms_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _loadingProvider;

  bool get _isLoading => _loadingProvider != null;

  Future<void> _signIn(String provider) async {
    if (_isLoading) return;

    final agreed = await _agreeToTerms(provider == 'kakao' ? '카카오' : 'Google');
    if (!agreed) return;

    setState(() => _loadingProvider = provider);
    try {
      final profile = provider == 'kakao'
          ? await AuthService.instance.signInWithKakao()
          : await AuthService.instance.signInWithGoogle();
      await _routeAfterLogin(profile);
    } on AuthException catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  Future<bool> _agreeToTerms(String providerLabel) async {
    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TermsAgreementScreen(providerLabel: providerLabel),
      ),
    );
    return agreed ?? false;
  }

  Future<void> _routeAfterLogin(AppAuthProfile profile) async {
    final savedNickname = await AuthService.instance.getNickname();
    if (!mounted) return;

    final needsSignUp = profile.isNewUser || savedNickname == null || savedNickname.isEmpty;
    if (needsSignUp) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignUpScreen(
            suggestedNickname: profile.nickname,
            suggestedPhotoUrl: profile.photoUrl,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  void _showError(AuthException e) {
    if (e.isUserCancel || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _LoginBackgroundSlideshow(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x59000000),
                    Color(0x1F000000),
                    Color(0x40000000),
                    Color(0xB3000000),
                  ],
                  stops: [0.0, 0.3, 0.6, 1.0],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    // 워드마크 기본은 21px. 여기는 히어로라 예외로 키움.
                    Text(
                      '온길',
                      style: AppTextStyles.logo.copyWith(
                        fontSize: 40,
                        color: AppColors.accent,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '기억 속 그 장소로 돌아가는 길,\n온길과 함께 걸어보세요',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heroCopy.copyWith(
                        fontSize: 15.5,
                        color: Colors.white.withValues(alpha: 0.95),
                        shadows: const [
                          Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 1)),
                        ],
                      ),
                    ),
                    const Spacer(flex: 4),
                    _KakaoButton(
                      label: '카카오로 시작하기',
                      loading: _loadingProvider == 'kakao',
                      onPressed: _isLoading ? null : () => _signIn('kakao'),
                    ),
                    const SizedBox(height: 10),
                    _GoogleButton(
                      label: 'Google로 계속하기',
                      loading: _loadingProvider == 'google',
                      onPressed: _isLoading ? null : () => _signIn('google'),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    // 캡션 기본색(textSecondary)은 사진 위에서 안 보여 흰색으로 예외.
                    Text(
                      '계속 진행 시 이용약관과\n개인정보처리방침에 동의하게 됩니다',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KakaoButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _KakaoButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFEE500),
          disabledBackgroundColor: const Color(0xFFFEE500),
          foregroundColor: const Color(0xFF191600),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF191600)),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const KakaoMark(size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF191600),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _GoogleButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardBackground,
          disabledBackgroundColor: AppColors.cardBackground,
          side: const BorderSide(color: AppColors.line, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.text),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoogleMark(size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: AppTextStyles.button.copyWith(color: AppColors.text),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LoginBackgroundSlideshow extends StatefulWidget {
  const _LoginBackgroundSlideshow();

  @override
  State<_LoginBackgroundSlideshow> createState() => _LoginBackgroundSlideshowState();
}

class _LoginBackgroundSlideshowState extends State<_LoginBackgroundSlideshow> {
  // 낮→노을→밤 순서라 정렬 바꾸지 말 것.
  static const List<String> _images = [
    'assets/images/ongil_1.jpg',
    'assets/images/ongil_2.jpg',
    'assets/images/ongil_3.jpg',
    'assets/images/ongil_4.jpg',
    'assets/images/ongil_5.jpg',
    'assets/images/ongil_6.jpg',
    'assets/images/ongil_7.jpg',
    'assets/images/ongil_8.jpg',
    'assets/images/ongil_9.jpg',
  ];

  static const _holdDuration = Duration(seconds: 5);
  static const _fadeDuration = Duration(milliseconds: 1200);

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_holdDuration, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _images.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _fadeDuration,
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: Image.asset(
        _images[_index],
        key: ValueKey(_images[_index]),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.pastPhotoFrom, AppColors.pastPhotoTo],
              ),
            ),
          );
        },
      ),
    );
  }
}
