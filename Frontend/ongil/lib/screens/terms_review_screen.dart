import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_top_bar.dart';
import '../models/terms_item.dart';

/// 설정 > 약관동의서 다시보기. 체크박스 없이 읽기 전용으로 약관을 다시 보여주는 화면.
class TermsReviewScreen extends StatelessWidget {
  const TermsReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppBackTopBar(title: '약관동의서 다시보기'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenHorizontal,
                  vertical: 8,
                ),
                itemCount: AppTerms.items.length,
                separatorBuilder: (_, __) => const Divider(color: AppColors.line, height: 28),
                itemBuilder: (context, i) => _TermsSection(item: AppTerms.items[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermsSection extends StatelessWidget {
  final TermsItem item;
  const _TermsSection({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              item.isRequired ? '[필수] ' : '[선택] ',
              style: AppTextStyles.bodySmall.copyWith(
                color: item.isRequired ? AppColors.accent : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(child: Text(item.title, style: AppTextStyles.cardTitle)),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          item.content,
          style: AppTextStyles.body.copyWith(height: 1.6),
        ),
      ],
    );
  }
}
