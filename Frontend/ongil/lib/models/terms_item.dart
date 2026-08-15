/// TermsAgreementScreen과 TermsReviewScreen이 공용으로 쓰는 약관 데이터.
/// TODO: 실제 약관 전문은 법무 검토 후 content에 채워 넣어야 함.
class TermsItem {
  final String title;
  final bool isRequired;
  final String content;

  const TermsItem({
    required this.title,
    required this.isRequired,
    required this.content,
  });
}

class AppTerms {
  AppTerms._();

  static const items = [
    TermsItem(
      title: '이용약관 동의',
      isRequired: true,
      content: 'TODO: 온길 서비스 이용약관 전문이 이 자리에 들어갑니다.',
    ),
    TermsItem(
      title: '개인정보 수집 및 이용 동의',
      isRequired: true,
      content: 'TODO: 개인정보 수집·이용에 대한 안내 전문이 이 자리에 들어갑니다.',
    ),
    TermsItem(
      title: '마케팅 정보 수신 동의',
      isRequired: false,
      content: 'TODO: 이벤트/혜택 등 마케팅 정보 수신에 대한 안내 전문이 이 자리에 들어갑니다.',
    ),
  ];
}
