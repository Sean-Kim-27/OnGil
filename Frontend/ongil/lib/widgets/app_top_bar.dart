import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 뒤로가기 있는 화면 공용 상단바.
/// 패딩은 스펙 값(top 14 / horizontal 16 / bottom 10) 그대로 사용.
/// Scaffold.appBar가 아니라 body 안 SafeArea 최상단에 직접 배치해서 쓰기
/// 위젯 (홈 화면의 상단바 구성 방식과 동일하게 맞춤).
class AppBackTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const AppBackTopBar({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.topBarHorizontal,
        AppSpacing.topBarTop,
        AppSpacing.topBarHorizontal,
        AppSpacing.topBarBottom,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardBackground,
                border: Border.all(color: AppColors.line, width: 1),
              ),
              child: const Icon(Icons.arrow_back_ios_new, size: 14, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 10),
          Text(title, style: AppTextStyles.screenTitle),
        ],
      ),
    );
  }
}
