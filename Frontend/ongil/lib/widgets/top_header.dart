import 'package:flutter/material.dart';

class TopHeader extends StatelessWidget {
  const TopHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween, // 양 끝 정렬 (로고 - 아이콘들)
        children: [
          // 1. 왼쪽 '온길' 로고
          const Text(
            '온길',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFFC85A32), // 온길 시그니처 테라코타 오렌지
            ),
          ),

          // 2. 오른쪽 검색 & 설정 아이콘
          Row(
            children: const [
              Icon(Icons.search, size: 26),
              SizedBox(width: 12),
              Icon(Icons.settings_outlined, size: 26),
            ],
          ),
        ],
      ),
    );
  }
}