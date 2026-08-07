import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 기본 카드: 1px 헤어라인 테두리, 카드 배경색, radius 14~16px
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool large;
  final bool selected;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.large = false,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        large ? AppRadius.cardLarge : AppRadius.card,
      ),
      child: Material(
        color: AppColors.cardBackground,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding ??
                EdgeInsets.all(
                  large ? AppSpacing.cardPaddingLarge : AppSpacing.cardPadding,
                ),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? AppColors.accent : AppColors.line,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(
                large ? AppRadius.cardLarge : AppRadius.card,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PillTag extends StatelessWidget {
  final String text;
  final Color background;

  const PillTag({
    super.key,
    required this.text,
    this.background = AppColors.accentLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
