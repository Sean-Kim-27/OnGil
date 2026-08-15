import 'package:flutter/material.dart';
import '../controllers/schedule_detail_controller.dart';

class ScheduleDetailScreen extends StatefulWidget {
  final String scheduleId;

  const ScheduleDetailScreen({
    super.key,
    required this.scheduleId,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
  final ScheduleDetailController _controller = ScheduleDetailController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      setState(() {});
    });
    _controller.loadScheduleDetail(widget.scheduleId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String? iconType) {
    switch (iconType) {
      case 'school':
        return Icons.school_outlined;
      case 'building':
        return Icons.account_balance_outlined;
      case 'restaurant':
        return Icons.restaurant_outlined;
      case 'home':
        return Icons.home_outlined;
      default:
        return Icons.place_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);
    const cardBgColor = Colors.white;
    const iconBoxBg = Color(0xFFEADBCE);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2C2825), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Color(0xFF2C2825)),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: _controller.isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryColor))
            : _controller.errorMessage != null
                ? Center(child: Text(_controller.errorMessage!))
                : Column(
                    children: [
                      // 1. 헤더 타이틀 정보
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _controller.scheduleDetail?['title'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                                if (_controller.scheduleDetail?['tag'] != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    _controller.scheduleDetail!['tag'],
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE2A84B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _controller.scheduleDetail?['subtitle'] ?? '',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF8A827A),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. 타임라인 리스트
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: (_controller.scheduleDetail?['timeline'] as List? ?? []).length,
                          itemBuilder: (context, index) {
                            final item = _controller.scheduleDetail!['timeline'][index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardBgColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFEFEBE4)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // 순서 & 아이콘 박스
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: iconBoxBg,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Icon(
                                          _getCategoryIcon(item['icon']),
                                          color: const Color(0xFF8A827A),
                                          size: 26,
                                        ),
                                        Positioned(
                                          top: 4,
                                          left: 6,
                                          child: Text(
                                            '${item['order']}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // 내용
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              item['name'],
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2C2825),
                                              ),
                                            ),
                                            Text(
                                              item['time'],
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: primaryColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item['memo'],
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF8A827A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}