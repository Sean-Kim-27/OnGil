import 'package:flutter/material.dart';
import '../models/guestbook_entry.dart';
import '../models/memory_archive_entry.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/before_after_slider.dart';
import '../widgets/memory_photo.dart';

/// 방명록 화면. '방명록'(글 목록) / '아카이브'(그때-지금 사진 비교) 두 탭으로 구성됨.
///
/// 아직 백엔드 API가 없어서(guestbook 라우터가 비어있음) 화면 안에서만 도는 더미
/// 데이터로 채워둠. 나중에 서버 연동할 때는 _seedEntries/_seedArchive 자리를
/// GuestbookService 같은 걸로 바꿔치기만 하면 되게 구조를 나눠둠.
class GuestbookScreen extends StatefulWidget {
  const GuestbookScreen({super.key});

  @override
  State<GuestbookScreen> createState() => _GuestbookScreenState();
}

class _GuestbookScreenState extends State<GuestbookScreen> {
  int _tabIndex = 0; // 0: 방명록, 1: 아카이브

  // 홈에서 검색한 장소를 아직 여기까지 연결하진 않아서, 지금은 고정값으로 보여줌.
  // 나중엔 PlaceService에서 마지막 검색 지역을 받아와 채우면 됨.
  static const _journeyLabel = '탄금대 · 충주';

  final List<GuestbookEntry> _entries = _seedEntries();
  final List<MemoryArchiveEntry> _archive = _seedArchive();

  static List<GuestbookEntry> _seedEntries() {
    final now = DateTime.now();
    return [
      GuestbookEntry(
        id: 'g1',
        placeName: '탄금대',
        authorName: '지훈',
        content: '10년 만에 다시 온 탄금대, 그대로라 눈물 날 뻔했어요.',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      GuestbookEntry(
        id: 'g2',
        placeName: '구도심 골목카페',
        authorName: '서연',
        content: '구도심 골목카페 사장님이 여전히 친절하셨어요. 감사~',
        createdAt: now.subtract(const Duration(days: 7)),
      ),
      GuestbookEntry(
        id: 'g3',
        placeName: '충주 손칼국수',
        authorName: '민재',
        content: '손칼국수 맛은 그대로인데 가게가 조금 넓어졌더라고요.',
        createdAt: now.subtract(const Duration(days: 14)),
      ),
    ];
  }

  static List<MemoryArchiveEntry> _seedArchive() {
    return const [
      MemoryArchiveEntry(
        id: 'a1',
        placeName: '탄금대',
        subtitle: '충주 · 모교 앞 골목',
        beforeYear: '1988',
        afterYear: '2026',
      ),
      MemoryArchiveEntry(
        id: 'a2',
        placeName: '탄금대',
        subtitle: '충주 · 강변 산책로',
        beforeYear: '1998',
        afterYear: '2026',
      ),
      MemoryArchiveEntry(
        id: 'a3',
        placeName: '탄금대',
        subtitle: '충주 · 시장 골목',
        beforeYear: '2001',
        afterYear: '2026',
      ),
      MemoryArchiveEntry(
        id: 'a4',
        placeName: '탄금대',
        subtitle: '충주 · 정류장 앞',
        beforeYear: '1995',
        afterYear: '2026',
      ),
    ];
  }

  void _openAddSheet() {
    final placeCtrl = TextEditingController(
      text: _entries.isNotEmpty ? _entries.first.placeName : '',
    );
    final contentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardLarge)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('새 방명록 남기기', style: AppTextStyles.screenTitle),
                const SizedBox(height: 16),
                TextField(
                  controller: placeCtrl,
                  style: AppTextStyles.input,
                  decoration: InputDecoration(
                    labelText: '장소',
                    hintText: '예: 탄금대 · 충주',
                    hintStyle: AppTextStyles.inputHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  style: AppTextStyles.input,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '기억',
                    hintText: '이 장소에서의 기억을 자유롭게 남겨보세요',
                    hintStyle: AppTextStyles.inputHint,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final place = placeCtrl.text.trim();
                      final content = contentCtrl.text.trim();
                      if (place.isEmpty || content.isEmpty) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(content: Text('장소와 기억을 모두 입력해주세요')),
                        );
                        return;
                      }
                      setState(() {
                        _entries.insert(
                          0,
                          GuestbookEntry(
                            id: DateTime.now().microsecondsSinceEpoch.toString(),
                            placeName: place,
                            authorName: '나',
                            content: content,
                            createdAt: DateTime.now(),
                          ),
                        );
                        _tabIndex = 0;
                      });
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('등록하기', style: AppTextStyles.button),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _GuestbookTopBar(onAddTap: _openAddSheet),
          _GuestbookTabs(
            index: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
          Expanded(
            child: _tabIndex == 0
                ? _GuestbookListTab(entries: _entries, journeyLabel: _journeyLabel)
                : _GuestbookArchiveTab(archive: _archive),
          ),
        ],
      ),
    );
  }
}

/// 화면 상단 - 타이틀 + 새 방명록 작성 버튼.
class _GuestbookTopBar extends StatelessWidget {
  final VoidCallback onAddTap;
  const _GuestbookTopBar({required this.onAddTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        14,
        AppSpacing.screenHorizontal,
        4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('방명록', style: AppTextStyles.heroGreeting.copyWith(fontSize: 21)),
          GestureDetector(
            onTap: onAddTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.add, color: AppColors.cardBackground, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// '방명록' / '아카이브' 탭 전환 바.
class _GuestbookTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _GuestbookTabs({required this.index, required this.onChanged});

  static const _labels = ['방명록', '아카이브'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 22),
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _labels[i],
                      style: AppTextStyles.cardTitle.copyWith(
                        color: index == i ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: index == i ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 2.5,
                      width: 28,
                      color: index == i ? AppColors.accent : Colors.transparent,
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

/// '방명록' 탭 - 장소별로 남긴 글 목록.
class _GuestbookListTab extends StatelessWidget {
  final List<GuestbookEntry> entries;
  final String journeyLabel;
  const _GuestbookListTab({required this.entries, required this.journeyLabel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: _JourneyBadge(label: journeyLabel),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '아직 남긴 방명록이 없어요. 오른쪽 위 + 버튼으로 첫 기억을 남겨보세요',
                      style: AppTextStyles.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    10,
                    AppSpacing.screenHorizontal,
                    100,
                  ),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
                  itemBuilder: (context, i) => _GuestbookEntryCard(entry: entries[i]),
                ),
        ),
      ],
    );
  }
}

/// "탄금대 · 충주 여정 기준" 처럼, 지금 보고 있는 방명록이 어떤 여정/장소 기준인지 알려주는 배지.
class _JourneyBadge extends StatelessWidget {
  final String label;
  const _JourneyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.brandLight.withOpacity(0.55),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          '$label 여정 기준',
          style: AppTextStyles.caption.copyWith(color: AppColors.text, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _GuestbookEntryCard extends StatelessWidget {
  final GuestbookEntry entry;
  const _GuestbookEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPaddingLarge),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AuthorAvatar(name: entry.authorName),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.authorName,
                  style: AppTextStyles.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(entry.relativeDate, style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.content, style: AppTextStyles.body, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          _PlaceTag(label: entry.placeName),
        ],
      ),
    );
  }
}

/// 작성자 이름을 그대로 보여주는 동그란 아바타. 실제 프로필 사진 대신 이니셜(짧은 한글
/// 이름이면 이름 전체) 텍스트로 대체함.
class _AuthorAvatar extends StatelessWidget {
  final String name;
  const _AuthorAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final label = name.length > 2 ? name.substring(0, 2) : name;
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.accentLight,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// 카드 하단의 장소 태그 pill. (예: 📍 탄금대)
class _PlaceTag extends StatelessWidget {
  final String label;
  const _PlaceTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accentLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: AppIconSize.inCardSmall, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// '아카이브' 탭 - 그때/지금 비교 슬라이더 + 다른 추억 그리드.
class _GuestbookArchiveTab extends StatefulWidget {
  final List<MemoryArchiveEntry> archive;
  const _GuestbookArchiveTab({required this.archive});

  @override
  State<_GuestbookArchiveTab> createState() => _GuestbookArchiveTabState();
}

class _GuestbookArchiveTabState extends State<_GuestbookArchiveTab> {
  late MemoryArchiveEntry _featured = widget.archive.first;

  @override
  Widget build(BuildContext context) {
    final others = widget.archive.where((a) => a.id != _featured.id).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        14,
        AppSpacing.screenHorizontal,
        100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '가운데 선을 좌우로 밀어 그때와 지금을 비교해보세요',
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 4),
          Text(
            _featured.subtitle,
            style: AppTextStyles.caption.copyWith(color: AppColors.brandMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          BeforeAfterSlider(
            beforeImage: _featured.beforeImage,
            afterImage: _featured.afterImage,
            beforeLabel: _featured.beforeYear,
            afterLabel: _featured.afterYear,
          ),
          const SizedBox(height: AppSpacing.sectionGap),
          const Text('다른 추억 둘러보기', style: AppTextStyles.cardTitle),
          const SizedBox(height: 10),
          if (others.isEmpty)
            const Text('둘러볼 다른 추억이 아직 없어요', style: AppTextStyles.bodySmall)
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: others.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.cardGap,
                mainAxisSpacing: AppSpacing.cardGap,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, i) {
                final item = others[i];
                return _ArchiveGridCard(
                  entry: item,
                  onTap: () => setState(() => _featured = item),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ArchiveGridCard extends StatelessWidget {
  final MemoryArchiveEntry entry;
  final VoidCallback onTap;
  const _ArchiveGridCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MemoryPhotoHero(
              image: entry.afterImage,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.placeName,
                    style: AppTextStyles.cardTitle.copyWith(color: AppColors.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '눌러서 비교해보기',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
