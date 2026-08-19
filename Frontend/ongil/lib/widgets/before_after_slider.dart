import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// '그때와 지금' 비교 슬라이더.
/// 가운데 손잡이를 좌우로 끌거나 탭하면 과거/현재 사진의 노출 비율이 바뀜.
/// 실제 사진이 없으면(image == null) 브랜드 톤 플레이스홀더로 대체해서 보여줌.
class BeforeAfterSlider extends StatefulWidget {
  final ImageProvider? beforeImage;
  final ImageProvider? afterImage;
  final String beforeLabel;
  final String afterLabel;
  final double height;

  const BeforeAfterSlider({
    super.key,
    this.beforeImage,
    this.afterImage,
    required this.beforeLabel,
    required this.afterLabel,
    this.height = 260,
  });

  @override
  State<BeforeAfterSlider> createState() => _BeforeAfterSliderState();
}

class _BeforeAfterSliderState extends State<BeforeAfterSlider> {
  // 0.0(전부 과거 사진) ~ 1.0(전부 최근 사진)
  double _position = 0.5;

  void _updateFromLocalDx(double dx, double width) {
    if (width <= 0) return;
    setState(() => _position = (dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.cardHero),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final handleX = (width * _position).clamp(0.0, width);

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _updateFromLocalDx(d.localPosition.dx, width),
            onTapDown: (d) => _updateFromLocalDx(d.localPosition.dx, width),
            child: SizedBox(
              height: widget.height,
              width: width,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 뒤 레이어: 최근 사진 (전체 노출)
                  _PhotoLayer(image: widget.afterImage, tone: _Tone.recent),
                  // 앞 레이어: 과거 사진 (왼쪽 부분만 잘라서 보여줌)
                  ClipRect(
                    clipper: _LeftClipper(handleX),
                    child: _PhotoLayer(image: widget.beforeImage, tone: _Tone.past),
                  ),
                  // 라벨 pill
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _LabelPill(text: widget.beforeLabel),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _LabelPill(text: widget.afterLabel),
                  ),
                  // 가운데 구분선
                  Positioned(
                    left: handleX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppColors.cardBackground),
                  ),
                  // 드래그 손잡이
                  Positioned(
                    left: (handleX - 18).clamp(0.0, width - 36),
                    top: widget.height / 2 - 18,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.swap_horiz, size: 18, color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _Tone { past, recent }

class _PhotoLayer extends StatelessWidget {
  final ImageProvider? image;
  final _Tone tone;
  const _PhotoLayer({required this.image, required this.tone});

  @override
  Widget build(BuildContext context) {
    final gradient = tone == _Tone.past
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFCBB48C), Color(0xFFB79A6E)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandLight, AppColors.accentLight],
          );

    return Container(
      decoration: BoxDecoration(
        gradient: image == null ? gradient : null,
        image: image != null
            ? DecorationImage(image: image!, fit: BoxFit.cover, onError: (_, __) {})
            : null,
      ),
      child: image == null
          ? Center(
              child: Icon(
                tone == _Tone.past ? Icons.photo_camera_back_outlined : Icons.landscape_outlined,
                size: 34,
                color: AppColors.cardBackground.withOpacity(0.75),
              ),
            )
          : null,
    );
  }
}

class _LabelPill extends StatelessWidget {
  final String text;
  const _LabelPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(color: AppColors.text, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 왼쪽부터 [width]까지만 남기고 나머지는 잘라내는 클리퍼.
class _LeftClipper extends CustomClipper<Rect> {
  final double width;
  _LeftClipper(this.width);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, width, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) => oldClipper.width != width;
}
