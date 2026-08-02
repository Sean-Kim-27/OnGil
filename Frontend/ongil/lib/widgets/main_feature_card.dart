import 'package:flutter/material.dart';

class MainFeatureCard extends StatelessWidget {
  const MainFeatureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                      color: Colors.white.withOpacity(0.6),
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
      ),
    );
  }
}