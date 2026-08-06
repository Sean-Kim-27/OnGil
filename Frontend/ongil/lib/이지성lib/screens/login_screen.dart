import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/brand_marks.dart';
import '../services/auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 두 버튼 중 지금 로그인 진행 중인 쪽만 표시하기 위한 상태.
  // ('google' | 'kakao' | null)
  String? _loadingProvider;

  bool get _isLoading => _loadingProvider != null;

  Future<void> _handleGoogle() async {
    setState(() => _loadingProvider = 'google');
    try {
      final profile = await AuthService.instance.signInWithGoogle();
      _goToSignUp(profile);
    } on AuthException catch (e) {
      _showErrorIfNeeded(e);
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  Future<void> _handleKakao() async {
    setState(() => _loadingProvider = 'kakao');
    try {
      final profile = await AuthService.instance.signInWithKakao();
      _goToSignUp(profile);
    } on AuthException catch (e) {
      _showErrorIfNeeded(e);
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  void _goToSignUp(AppAuthProfile profile) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignUpScreen(
          suggestedNickname: profile.nickname,
          suggestedPhotoUrl: profile.photoUrl,
        ),
      ),
    );
  }

  void _showErrorIfNeeded(AuthException e) {
    // 사용자가 그냥 취소한 경우엔 에러로 취급하지 않고 조용히 넘어가게 둠
    if (e.isUserCancel || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Text(
                '온길',
                style: AppTextStyles.logo.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: 10),
              const Text(
                '기억 속 그 장소로 돌아가는 길,\n온길과 함께 걸어보세요',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
              const Spacer(flex: 4),
              _KakaoButton(
                label: '카카오로 시작하기',
                loading: _loadingProvider == 'kakao',
                onPressed: _isLoading ? null : _handleKakao,
              ),
              const SizedBox(height: 10),
              _GoogleButton(
                label: 'Google로 계속하기',
                loading: _loadingProvider == 'google',
                onPressed: _isLoading ? null : _handleGoogle,
              ),
              const SizedBox(height: AppSpacing.sectionGap),
              const Text(
                '계속 진행 시 이용약관과\n개인정보처리방침에 동의하게 됩니다',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카카오 로그인 버튼 - 브랜드 컬러인 노란색(#FEE500)만 예외로 사용.
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

/// Google 로그인 버튼 - 아웃라인(고스트) 스타일.
/// 화면당 강한 액센트 버튼은 최대 1개 규칙을 지키기 위해 카카오 버튼과 달리 채움 스타일을 쓰지 않음.
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
