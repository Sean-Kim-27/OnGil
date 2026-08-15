import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import 'memory_photo.dart';

/// 홈 화면 메인 카드: '그때와 지금' 추억 하이라이트.
/// tag/title/subtitle을 안 넘기면 아직 검색 전 상태의 기본 문구가 나타남  -
/// 검색으로 대표 장소가 정해지면 그 값을 넘겨서 실제 내용으로 바꿔서 나타나게함
class MainFeatureCard extends StatelessWidget {
  final String? tag;
  final String? title;
  final String? subtitle;
  final ImageProvider? image;
  final VoidCallback? onTap;

  const MainFeatureCard({
    super.key,
    this.tag,
    this.title,
    this.subtitle,
    this.image,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 카드 상단 (그라데이션 & 충주 1998 뱃지)
          Container(
            height: 200,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEADBCE), Color(0xFFD3BCA8)],
              ),
            ),
            child: Stack(
              children: [
                const Positioned(
                  top: 16,
                  left: 16,
                  child: Icon(Icons.image_outlined, color: Colors.white70, size: 28),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFC85A32), width: 1.2),
                    ),
                    child: const Text(
                      '충주 · 1998',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC85A32),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 카드 하단 (타이틀 & 내용 & 비교해보기 링크)
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // ⭐ 서브 타이틀
                const Text(
                  'THEN & NOW',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC39B6B),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),

                // ⭐ 메인 타이틀
                const Text(
                  '그 골목, 지금은\n어떤 모습일까요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2825),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),

                // ⭐ 설명문
                Text(
                  '초등학교 앞 문구점 자리를 다시 찾아가는 길',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),

                // ⭐ 하단 링크
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      '그때와 지금 비교해보기',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC85A32),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: Color(0xFFC85A32)),
                  ],
                ),
              ],
            ),
          ),
        ],
=======
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.cardHero),
          border: Border.all(color: AppColors.warmCardBorder),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhotoHeader(tag: tag ?? '충주 · 1998', image: image),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'THEN & NOW',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.brandMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title ?? '그 골목, 지금은\n어떤 모습일까요',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heroCopy,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle ?? '초등학교 앞 문구점 자리를 다시 찾아가는 길',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '그때와 지금 비교해보기',
                        style: AppTextStyles.body.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 16, color: AppColors.accent),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
>>>>>>> 181b2e02e01fc09c9df58fdd7b41b573330de210
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  final String tag;
  final ImageProvider? image;
  const _PhotoHeader({required this.tag, this.image});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MemoryPhotoHero(
          image: image,
          height: 200,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardHero)),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withOpacity(0.6),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.accent, width: 1.2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                tag,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
