import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/photo_source_sheet.dart';
import '../services/auth_service.dart';
import '../services/photo_service.dart';
import 'terms_review_screen.dart';

/// 설정 화면: 프로필 사진 변경 / 약관동의서 다시보기 / 로그아웃 / 회원탈퇴를 모아둠.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _nickname;
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final nickname = await AuthService.instance.getNickname();
    final photoUrl = await AuthService.instance.getPhotoUrl();
    if (!mounted) return;
    setState(() {
      _nickname = nickname;
      _photoUrl = photoUrl;
    });
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
        title: const Text('닉네임 변경', style: AppTextStyles.screenTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTextStyles.input,
          decoration: const InputDecoration(hintText: '닉네임을 입력해주세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text(
              '저장',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || result == _nickname) return;

    await AuthService.instance.saveUserProfile(nickname: result);
    // TODO: 백엔드 프로필 수정 API 명세가 나오면 여기서 서버에도 반영 필요.
    if (!mounted) return;
    setState(() => _nickname = result);
  }

  Future<void> _changeProfilePhoto() async {
    final source = await showPhotoSourceSheet(context);
    if (source == null) return;

    final savedPath = await PhotoService.instance.pickAndSaveProfilePhoto(source: source);
    if (savedPath == null) return;

    await AuthService.instance.saveUserProfile(photoUrl: savedPath);
    // TODO: 백엔드 이미지 업로드 API가 생기면 여기서 서버 업로드도 반영 필요.
    if (!mounted) return;
    setState(() => _photoUrl = savedPath);
  }

  Future<void> _logout() async {
    final confirmed = await _confirmDialog(
      title: '로그아웃 하시겠어요?',
      message: '다시 로그인하면 이어서 이용할 수 있어요.',
      confirmLabel: '로그아웃',
    );
    if (confirmed != true) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirmDialog(
      title: '정말 탈퇴하시겠어요?',
      message: '탈퇴하면 기록된 추억과 계정 정보가 모두 삭제되며 복구할 수 없어요.',
      confirmLabel: '탈퇴하기',
      destructive: true,
    );
    if (confirmed != true) return;
    await AuthService.instance.deleteAccount();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardLarge)),
        title: Text(title, style: AppTextStyles.screenTitle),
        content: Text(message, style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: destructive ? AppColors.accent : AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppBackTopBar(title: '설정'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                children: [
                  const SizedBox(height: 4),
                  _ProfileSummary(
                    nickname: _nickname ?? '온길 회원',
                    photoUrl: _photoUrl,
                    onPhotoTap: _changeProfilePhoto,
                    onNicknameTap: _editNickname,
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  _SettingsTile(
                    icon: Icons.edit_outlined,
                    label: '닉네임 변경',
                    onTap: _editNickname,
                  ),
                  _SettingsTile(
                    icon: Icons.photo_camera_outlined,
                    label: '프로필 사진 변경',
                    onTap: _changeProfilePhoto,
                  ),
                  _SettingsTile(
                    icon: Icons.description_outlined,
                    label: '약관동의서 다시보기',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TermsReviewScreen()),
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.logout,
                    label: '로그아웃',
                    onTap: _logout,
                  ),
                  _SettingsTile(
                    icon: Icons.person_remove_outlined,
                    label: '회원탈퇴',
                    labelColor: AppColors.accent,
                    onTap: _deleteAccount,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  final String nickname;
  final String? photoUrl;
  final VoidCallback onPhotoTap;
  final VoidCallback onNicknameTap;

  const _ProfileSummary({
    required this.nickname,
    this.photoUrl,
    required this.onPhotoTap,
    required this.onNicknameTap,
  });

  @override
  Widget build(BuildContext context) {
    final image = resolveProfileImage(photoUrl);
    return Row(
      children: [
        GestureDetector(
          onTap: onPhotoTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cardBackground,
                  border: Border.all(color: AppColors.line, width: 1),
                  image: image == null
                      ? null
                      : DecorationImage(image: image, fit: BoxFit.cover, onError: (_, __) {}),
                ),
                child: image == null
                    ? const Icon(Icons.person_outline, size: 28, color: AppColors.textSecondary)
                    : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent,
                    border: Border.all(color: AppColors.background, width: 2),
                  ),
                  child: const Icon(Icons.photo_camera, size: 11, color: AppColors.cardBackground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: GestureDetector(
            onTap: onNicknameTap,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    '$nickname님',
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 15, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: labelColor ?? AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: labelColor ?? AppColors.text,
                  fontSize: 13.5,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
