/// 온길 디자인 시스템 - 여백/모서리/아이콘 사이즈 토큰

class AppSpacing {
  AppSpacing._();

  /// 화면 좌우 기본 패딩
  static const screenHorizontal = 18.0;

  /// 상단바(뒤로가기 있는 화면) 패딩 - top / horizontal / bottom
  static const topBarTop = 14.0;
  static const topBarHorizontal = 16.0;
  static const topBarBottom = 10.0;

  /// 카드 내부 패딩
  static const cardPadding = 13.0; // 12~14px 사이 기본값
  static const cardPaddingLarge = 15.0; // 큰 카드는 14~16px

  /// 카드 사이 간격
  static const cardGap = 11.0; // 10~12px

  /// 섹션 사이 여백
  static const sectionGap = 19.0; // 18~20px

  /// 하단 고정바 패딩 - top / horizontal / bottom
  static const bottomBarTop = 14.0;
  static const bottomBarHorizontal = 18.0;
  static const bottomBarBottom = 20.0;
}

class AppRadius {
  AppRadius._();

  /// 폰 프레임 / 최상위 요소
  static const frame = 38.0;

  /// 큰 카드 (히어로 등)
  static const cardLarge = 18.0;

  /// 일반 카드
  static const card = 15.0; // 14~16px

  /// 썸네일 / 아이콘 박스
  static const thumbnail = 11.0; // 10~12px

  /// 버튼
  static const button = 13.0; // 12~14px

  /// 칩 / 배지 / 우표 뱃지 - 완전 원형
  static const pill = 999.0;

  /// 홈 화면 메인 피처 카드 (신규 디자인)
  static const cardHero = 24.0;

  /// 홈 화면 바로가기 카드 (신규 디자인)
  static const cardMedium = 20.0;
}

class AppIconSize {
  AppIconSize._();

  /// 하단 탭 아이콘
  static const bottomTab = 21.0;

  /// 카드 내 작은 아이콘 (지도핀, 별 등)
  static const inCardSmall = 12.0; // 10~13px

  /// 카테고리 아이콘 박스 (타임라인/썸네일)
  static const categoryBox = 44.0; // 34~56px
  static const categoryIcon = 17.0; // 15~19px 박스 안 아이콘
}
