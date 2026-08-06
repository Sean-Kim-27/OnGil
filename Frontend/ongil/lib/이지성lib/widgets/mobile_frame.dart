import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Windows/웹처럼 넓은 화면에서 테스트할 때, 인풋/버튼이 화면 끝까지
/// 쭉 늘어나 보이지 않도록 실제 폰 폭(430px)으로 중앙에 고정해서 보여줍니다.
class ResponsiveMobileFrame extends StatelessWidget {
  final Widget child;
  const ResponsiveMobileFrame({super.key, required this.child});

  static const double maxPhoneWidth = 430;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // 데스크톱에서 폰 프레임 바깥으로 보이는 여백 색
      color: const Color(0xFFEDE6D8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
          child: ColoredBox(
            color: AppColors.background,
            child: child,
          ),
        ),
      ),
    );
  }
}
