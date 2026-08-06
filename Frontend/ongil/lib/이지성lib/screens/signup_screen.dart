import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';

/// 회원가입 화면. 소셜 로그인에서 넘어온 닉네임/프로필 사진이 있으면 미리 채워주고, b사용자가 원하면 바로 수정할 수 있습니다.
/// 프로필 사진 업로드는 아직 실제 이미지 선택 로직 없이 틀만 해놈
class SignUpScreen extends StatefulWidget {
  final String? suggestedNickname;
  final String? suggestedPhotoUrl;

  const SignUpScreen({
    super.key,
    this.suggestedNickname,
    this.suggestedPhotoUrl,
  });

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  late final _nicknameCtrl = TextEditingController(text: widget.suggestedNickname ?? '');

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  void _startMemories(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppBackTopBar(title: '회원가입'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text('닉네임', style: AppTextStyles.caption),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nicknameCtrl,
                      style: AppTextStyles.input,
                      decoration: const InputDecoration(
                        hintText: '닉네임을 작성해주세요',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    const Text('프로필 사진', style: AppTextStyles.caption),
                    const SizedBox(height: 14),
                    Center(child: _ProfilePicker(photoUrl: widget.suggestedPhotoUrl)),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton(
                        onPressed: () {},
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                        ),
                        child: const Text('사진 추가하기'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.bottomBarHorizontal,
                AppSpacing.bottomBarTop,
                AppSpacing.bottomBarHorizontal,
                AppSpacing.bottomBarBottom,
              ),
              child: PrimaryButton(
                label: '추억 시작하기',
                onPressed: () => _startMemories(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 프로필 사진 자리표시자: 원형 아웃라인 + 사람 아이콘, 우하단에 카메라 뱃지. photoUrl이 있으면(구글/카카오 프로필 사진) 그 사진을 보여주고, 없거나 로딩에 실패하면  기본 이미지로로 대체합니다.
class _ProfilePicker extends StatelessWidget {
  final String? photoUrl;
  const _ProfilePicker({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardBackground,
              border: Border.all(color: AppColors.line, width: 1),
              image: photoUrl == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(photoUrl!),
                      fit: BoxFit.cover,
                      onError: (_, __) {},
                    ),
            ),
            child: photoUrl == null
                ? const Icon(
                    Icons.person_outline,
                    size: 36,
                    color: AppColors.textSecondary,
                  )
                : null,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
                border: Border.all(color: AppColors.background, width: 2),
                boxShadow: AppShadows.fab,
              ),
              child: const Icon(
                Icons.photo_camera,
                size: 15,
                color: AppColors.cardBackground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
