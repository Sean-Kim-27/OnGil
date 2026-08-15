import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 카드 캐러셀 아래에 있는 페이지 표시기. 
/// 실제 검색 결과가 많아도 숫자로 바꾸지 않고 항상 점으로만 표시하되, 화면에는 [maxVisible](점 기본 4개) 정도만 보이도록 현재 위치를 중심으로 나오게함
class PageDotsIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  final int maxVisible;

  const PageDotsIndicator({
    super.key,
    required this.count,
    required this.currentIndex,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();

    final windowSize = count < maxVisible ? count : maxVisible;
    final rawStart = currentIndex - windowSize ~/ 2;
    final start = rawStart.clamp(0, count - windowSize).toInt();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(windowSize, (offset) {
        final i = start + offset;
        final active = i == currentIndex;
        final isFirstInWindow = offset == 0;
        final isLastInWindow = offset == windowSize - 1;
        final hasMoreBeyond = (isFirstInWindow && start > 0) ||
            (isLastInWindow && start + windowSize < count);
        final dotSize = hasMoreBeyond ? 4.5 : 6.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18.0 : dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.line,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
