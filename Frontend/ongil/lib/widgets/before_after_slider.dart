import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';

/// '그때와 지금' 비교 슬라이더. 손잡이를 끌면 노출 비율이 바뀜.
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
                  _PhotoLayer(image: widget.afterImage, tone: _Tone.recent),
                  // 과거 사진은 왼쪽 부분만 잘라서 위에 얹음.
                  ClipRect(
                    clipper: _LeftClipper(handleX),
                    child: _PhotoLayer(image: widget.beforeImage, tone: _Tone.past),
                  ),
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
                  Positioned(
                    left: handleX - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppColors.cardBackground),
                  ),
                  Positioned(
                    left: (handleX - 18).clamp(0.0, width - 36),
                    top: widget.height / 2 - 18,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.fab,
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
            colors: [AppColors.pastPhotoFrom, AppColors.pastPhotoTo],
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
                color: AppColors.cardBackground.withValues(alpha: 0.75),
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
        color: AppColors.cardBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 왼쪽부터 [width]까지만 남기는 클리퍼.
class _LeftClipper extends CustomClipper<Rect> {
  final double width;
  _LeftClipper(this.width);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, width, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper oldClipper) => oldClipper.width != width;
}
