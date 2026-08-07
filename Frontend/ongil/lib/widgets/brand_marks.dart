import 'package:flutter/material.dart';

class GoogleMark extends StatelessWidget {
  final double size;
  const GoogleMark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/google_logo.png',
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GoogleGPainter()),
      ),
    );
  }
}

class KakaoMark extends StatelessWidget {
  final double size;
  const KakaoMark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/kakao_symbol.png',
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _KakaoBubblePainter()),
      ),
    );
  }
}

/// 구글 'G' 간이 벡터 버전 (정식 에셋 넣기 전 임시용 — 4색 링 + 가로 막대)
class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.22;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    paint.color = const Color(0xFF4285F4); // blue
    canvas.drawArc(rect, -0.45, 1.65, false, paint);
    paint.color = const Color(0xFF34A853); // green
    canvas.drawArc(rect, 1.20, 1.05, false, paint);
    paint.color = const Color(0xFFFBBC05); // yellow
    canvas.drawArc(rect, 2.25, 1.05, false, paint);
    paint.color = const Color(0xFFEA4335); // red
    canvas.drawArc(rect, 3.30, 1.20, false, paint);

    final barPaint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - strokeWidth * 0.1,
        center.dy - strokeWidth / 2,
        radius * 0.92,
        strokeWidth,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 카카오 말풍선 심볼 간이 벡터 버전 (정식 에셋 넣기 전 임시용)
class _KakaoBubblePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF191600);
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h * 0.76),
          Radius.circular(h * 0.4),
        ),
      )
      ..moveTo(w * 0.26, h * 0.68)
      ..lineTo(w * 0.16, h * 0.96)
      ..lineTo(w * 0.44, h * 0.72)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
