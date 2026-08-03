import 'package:flutter/material.dart';

class QuickActionCards extends StatelessWidget {
  const QuickActionCards({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Row(
        children: [
          // 1. 왼쪽: 지도 살펴보기 카드 (절반 차지)
          Expanded(
            child: Container(
              height: 110,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF3E8), // 은은한 연두빛 배경
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // 아이콘 상단, 텍스트 하단 배치
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFFC39B6B), size: 26),
                  Row(
                    children: const [
                      Text(
                        '지도 살펴보기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2825),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: Color(0xFF2C2825)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12), // 카드 사이의 가로 간격

          // 2. 오른쪽: 스케줄 보러가기 카드 (절반 차지)
          Expanded(
            child: Container(
              height: 110,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Icon(Icons.alt_route_rounded, color: Color(0xFFC39B6B), size: 26),
                  Text(
                    '스케줄 보러가기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}