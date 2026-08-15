import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/photo_source_sheet.dart';
import '../services/auth_service.dart';
import '../services/photo_service.dart';

/// 회원가입 화면. 소셜 로그인에서 넘어온 닉네임/프로필 사진이 있으면 미리 채워주고, 사용자가 원하면 바로 수정할 수 있게함.
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
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.suggestedPhotoUrl;
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showPhotoSourceSheet(context);
    if (source == null) return;

    final savedPath = await PhotoService.instance.pickAndSaveProfilePhoto(source: source);
    if (savedPath == null || !mounted) return;
    setState(() => _photoUrl = savedPath);
  }

  // 닉네임 저장 후 홈으로 이동. 홈 화면 인사말에서 AuthService.getNickname()으로 읽어감.
  Future<void> _startMemories() async {
    final nickname = _nicknameCtrl.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임을 입력해주세요')),
      );
      return;
    }

    await AuthService.instance.saveUserProfile(
      nickname: nickname,
      photoUrl: _photoUrl,
    );
    // TODO: 백엔드에 프로필(닉네임/사진) 등록하는 API 명세가 나오면 여기서 서버에도 반영 필요.

    if (!mounted) return;
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
                    Center(
                      child: _ProfilePicker(photoUrl: _photoUrl, onTap: _pickPhoto),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton(
                        onPressed: _pickPhoto,
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
                onPressed: _startMemories,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 프로필 사진: 기본으로 photoUrl이 있으면(구글/카카오 프로필 사진의 기본) 그 사진을 보여주고, 없으면 기본 아이콘을 대신 보여줍니다. 탭하면 onTap 호출.
class _ProfilePicker extends StatelessWidget {
  final String? photoUrl;
  final VoidCallback onTap;
  const _ProfilePicker({this.photoUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = resolveProfileImage(photoUrl);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
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
                image: image == null
                    ? null
                    : DecorationImage(image: image, fit: BoxFit.cover, onError: (_, __) {}),
              ),
              child: image == null
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
      ),
    );
  }
}
