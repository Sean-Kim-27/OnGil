import 'package:flutter/material.dart';
import 'ai_schedule_working.dart'; // 마지막 스텝 연동용

// 장소 데이터 모델
class PlaceItem {
  final String id;
  final String title;
  final String description;
  final double rating;
  final String distance;
  final IconData icon;

  PlaceItem({
    required this.id,
    required this.title,
    required this.description,
    required this.rating,
    required this.distance,
    required this.icon,
  });
}

// 각 스텝별 카테고리 정보 데이터 모델
class StepCategoryData {
  final String title;
  final String subtitle;
  final List<PlaceItem> places;

  StepCategoryData({
    required this.title,
    required this.subtitle,
    required this.places,
  });
}

class PlaceSelectScreen extends StatefulWidget {
  final int currentStep;
  final int totalSteps;

  const PlaceSelectScreen({
    super.key,
    this.currentStep = 1,
    this.totalSteps = 4,
  });

  @override
  State<PlaceSelectScreen> createState() => _PlaceSelectScreenState();
}

class _PlaceSelectScreenState extends State<PlaceSelectScreen> {
  final Set<String> _selectedPlaceIds = {};

  // ⭐ Step 1 ~ 4 단계별 데이터 정의
  late final List<StepCategoryData> _stepDataList = [
    // 1단계: 주요 관광지 / 명소
    StepCategoryData(
      title: '명소 추천',
      subtitle: '이번 여행에서 꼭 방문하고 싶은 장소는?',
      places: [
        PlaceItem(
          id: 's1_1',
          title: '탄금대 공원',
          description: '남한강을 내려다보는 울창한 소나무 숲길',
          rating: 4.8,
          distance: '차량 8분',
          icon: Icons.park_outlined,
        ),
        PlaceItem(
          id: 's1_2',
          title: '중앙탑 사적공원',
          description: '넓은 잔디밭과 야경이 아름다운 수변 공원',
          rating: 4.6,
          distance: '차량 15분',
          icon: Icons.account_balance_outlined,
        ),
        PlaceItem(
          id: 's1_3',
          title: '활옥동굴',
          description: '신비로운 신비의 동굴 보트 체험',
          rating: 4.7,
          distance: '차량 20분',
          icon: Icons.explore_outlined,
        ),
      ],
    ),

    // 2단계: 식당 / 맛집
    StepCategoryData(
      title: '맛집 추천',
      subtitle: '현지 느낌 물씬 풍기는 맛집을 골라보세요',
      places: [
        PlaceItem(
          id: 's2_1',
          title: '남한강 메기매운탕',
          description: '시원하고 칼칼한 국물이 일품인 로컬 맛집',
          rating: 4.6,
          distance: '차량 10분',
          icon: Icons.restaurant_outlined,
        ),
        PlaceItem(
          id: 's2_2',
          title: '중앙탑 막국수',
          description: '새싹 가득 시원한 막국수와 치킨 조합',
          rating: 4.5,
          distance: '차량 14분',
          icon: Icons.ramen_dining_outlined,
        ),
        PlaceItem(
          id: 's2_3',
          title: '옛날 한정식 집',
          description: '정갈한 정통 푸짐한 한상 차림',
          rating: 4.8,
          distance: '도보 12분',
          icon: Icons.rice_bowl_outlined,
        ),
      ],
    ),

    // 3단계: 카페 추천
    StepCategoryData(
      title: '카페 추천',
      subtitle: '여유롭게 쉬어갈 마음 드는 공간',
      places: [
        PlaceItem(
          id: 's3_1',
          title: '구도심 골목카페',
          description: '레트로 감성 가득한 동네 카페',
          rating: 4.7,
          distance: '도보 5분',
          icon: Icons.coffee_outlined,
        ),
        PlaceItem(
          id: 's3_2',
          title: '성내동 카페거리',
          description: '옛 시장 골목을 개조한 감성 카페',
          rating: 4.5,
          distance: '도보 9분',
          icon: Icons.coffee_outlined,
        ),
        PlaceItem(
          id: 's3_3',
          title: '탄금호 뷰카페',
          description: '호수가 내려다보이는 루프탑',
          rating: 4.8,
          distance: '차량 7분',
          icon: Icons.coffee_outlined,
        ),
        PlaceItem(
          id: 's3_4',
          title: '중앙탑 베이커리카페',
          description: '현지인 추천 빵집 겸 카페',
          rating: 4.4,
          distance: '차량 12분',
          icon: Icons.bakery_dining_outlined,
        ),
      ],
    ),

    // 4단계: 숙소 / 휴식공간
    StepCategoryData(
      title: '숙소 추천',
      subtitle: '편안한 밤을 책임질 추천 숙소',
      places: [
        PlaceItem(
          id: 's4_1',
          title: '탄금호 리버뷰 펜션',
          description: '창밖으로 호수가 바로 보이는 힐링 숙소',
          rating: 4.9,
          distance: '차량 10분',
          icon: Icons.hotel_outlined,
        ),
        PlaceItem(
          id: 's4_2',
          title: '도심 속 감성 한옥스테이',
          description: '고즈넉한 고택에서의 특별한 하룻밤',
          rating: 4.8,
          distance: '차량 5분',
          icon: Icons.other_houses_outlined,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFFC85A32);
    const bgColor = Color(0xFFFAF7F2);

    // 현재 스텝 데이터 가져오기 (인덱스는 0부터 시작하므로 -1)
    final currentCategory = _stepDataList[widget.currentStep - 1];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF2C2825)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    currentCategory.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2825),
                    ),
                  ),
                  const Spacer(),
                  // Step Badge (1 / 4)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFEBE4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${widget.currentStep} / ${widget.totalSteps}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8A827A),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Text(
              currentCategory.subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF8A827A),
              ),
            ),
            const SizedBox(height: 20),

            // 2. 카드리스트
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                itemCount: currentCategory.places.length,
                separatorBuilder: (context, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final place = currentCategory.places[index];
                  final isSelected = _selectedPlaceIds.contains(place.id);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedPlaceIds.remove(place.id);
                        } else {
                          _selectedPlaceIds.add(place.id);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? primaryColor : const Color(0xFFEFEBE4),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEADBCE).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(place.icon, color: const Color(0xFF8C7A6B), size: 26),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2C2825),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  place.description,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF8A827A),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.star_border_rounded, size: 14, color: Color(0xFFD3A15C)),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${place.rating} · ${place.distance}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFD3A15C),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? primaryColor : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? primaryColor : const Color(0xFFDDD7CD),
                                width: 1.5,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 18, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. 하단 바 (다음 스텝 이동 로직)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: bgColor,
                border: Border(top: BorderSide(color: Color(0xFFEFEBE4))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedPlaceIds.length}개 선택됨',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8A827A),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _selectedPlaceIds.isNotEmpty
                        ? () {
                            if (widget.currentStep < widget.totalSteps) {
                              // 다음 스텝(예: 1/4 -> 2/4)으로 이동
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlaceSelectScreen(
                                    currentStep: widget.currentStep + 1,
                                    totalSteps: widget.totalSteps,
                                  ),
                                ),
                              );
                            } else {
                              // 마지막 스텝(4/4)일 때: AI 생성 로딩 화면으로 연결!
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AiScheduleWorking(),
                                ),
                              );
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: primaryColor.withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      children: [
                        Text(
                          widget.currentStep < widget.totalSteps ? '다음' : '스케줄 생성',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}