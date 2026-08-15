import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// 홈 화면 검색창. 동네·학교 이름 등 주소를 입력하면 그 주변 추천 장소를 불러옴.
class HomeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const HomeSearchBar({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTextStyles.input,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: const InputDecoration(
        hintText: '동네, 학교 이름으로 검색해보세요',
        prefixIcon: Icon(Icons.search, size: 20, color: AppColors.textSecondary),
      ),
    );
  }
}
