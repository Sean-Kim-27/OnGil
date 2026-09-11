import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/app_shell_controller.dart';
import '../models/guestbook.dart';
import '../models/guestbook_entry.dart';
import '../models/memory_archive_entry.dart';
import '../models/moderation.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/guestbook_api_service.dart';
import '../services/moderation_api_service.dart';
import '../services/photo_service.dart';
import '../services/schedule_api_service.dart';
import '../services/user_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/before_after_slider.dart';
import '../widgets/memory_photo.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/report_sheet.dart';
import 'blocked_users_screen.dart';

/// 방명록 화면. '방명록'(글 목록) / '아카이브'(그때-지금 사진 비교) 두 탭.
///
/// 서버 기준으로 방명록은 **장소(place_id)당 한 건**이고, 그 한 건이 글과 사진을
/// 함께 들고 있다. 두 탭은 같은 레코드의 다른 단면이라, 아카이브의 메모를 고치면
/// 방명록 탭의 글도 같이 바뀐다.
///
/// 서버 제약 두 가지를 화면에서도 그대로 지킨다.
/// - 사진은 스팟당 CURRENT 1장 / PAST 1장 (교체·삭제 엔드포인트 없음)
/// - PAST는 CURRENT가 먼저 올라가 있어야 함 → 입력 순서가 '지금 → 그때'
class GuestbookScreen extends StatefulWidget {
  /// 처음 열 탭. 0:방명록 1:아카이브.
  /// 홈의 '그때와 지금' 카드처럼 아카이브를 바로 열고 싶을 때 1을 넘긴다.
  final int initialTabIndex;

  const GuestbookScreen({super.key, this.initialTabIndex = 0});

  @override
  State<GuestbookScreen> createState() => _GuestbookScreenState();
}

class _GuestbookScreenState extends State<GuestbookScreen> {
  late int _tabIndex; // 0: 방명록, 1: 아카이브

  bool _isLoading = true;

  /// 업로드/저장 중 화면을 잠그기 위한 플래그.
  bool _isSaving = false;

  /// 여정을 불러오지 못했을 때의 안내 문구.
  String? _errorMessage;

  /// 방명록 목록을 불러오지 못했을 때의 안내 문구.
  String? _guestbookError;

  ScheduleDetail? _schedule;
  String _authorName = '나';

  /// 서버에서 받은 원본을 place_id로 찾을 수 있게 들고 있음.
  final Map<int, Guestbook> _books = {};

  List<GuestbookEntry> _entries = [];
  List<MemoryArchiveEntry> _archive = [];

  /// 내 여정 장소에 달린 **모든 사용자**의 방명록. 방명록 탭이 이걸 보여준다.
  /// (아카이브 탭과 작성 시트는 여전히 내 것만 담긴 `_books`를 쓴다)
  List<GuestbookFeedItem> _feed = [];

  /// 방명록 탭 상단에서 고른 장소. null이면 전체.
  int? _selectedPlaceId;

  /// 서버가 아는 내 user id. 내 글에는 신고 대신 수정·삭제를 띄운다.
  int? _myUserId;

  /// 아카이브 탭에서 크게 비교 중인 장소.
  int? _featuredPlaceId;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex == 1 ? 1 : 0;
    _load();
  }

  @override
  void didUpdateWidget(covariant GuestbookScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 홈에서 '아카이브로 열어달라'고 다시 요청한 경우에만 탭을 옮긴다.
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      setState(() => _tabIndex = widget.initialTabIndex == 1 ? 1 : 0);
    }
  }

  // ---------------------------------------------------------------------------
  // 불러오기
  // ---------------------------------------------------------------------------

  /// 마지막 여정 + 내 방명록 전체를 함께 불러옴.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _guestbookError = null;
    });

    final nickname = await AuthService.instance.getNickname();
    final scheduleId = await ScheduleApiService.getLastScheduleId();

    // 내 글에는 신고 메뉴를 띄우지 않으려면 서버 기준 내 id가 필요하다.
    // 실패해도 화면은 그대로 뜬다.
    _myUserId =
        UserApiService.currentUserId ?? (await UserApiService.fetchMe())?.id;

    ScheduleDetail? detail;
    String? scheduleError;
    if (scheduleId != null) {
      try {
        detail = await ScheduleApiService.fetchScheduleDetail(scheduleId);
      } on ScheduleApiException catch (e) {
        scheduleError = e.userMessage;
      } catch (_) {
        scheduleError = '여정을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
      }
    }

    // 여정 조회가 실패해도 방명록은 따로 읽어둠.
    List<Guestbook> books = const [];
    String? bookError;
    try {
      books = await GuestbookApiService.fetchMyGuestbooks();
    } on GuestbookApiException catch (e) {
      bookError = e.userMessage;
    } catch (_) {
      bookError = '방명록을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
    }

    // 여정에 담긴 장소의 방명록을 모두 읽어온다(다른 사용자 글 포함).
    final feed = await _fetchFeedForSchedule(detail);

    if (!mounted) return;
    setState(() {
      _schedule = detail;
      _feed = feed;
      _selectedPlaceId = null;
      _errorMessage = scheduleError;
      _guestbookError = bookError;
      _authorName = (nickname == null || nickname.isEmpty) ? '나' : nickname;
      _books
        ..clear()
        ..addEntries(books.map((b) => MapEntry(b.placeId, b)));
      _isLoading = false;
      _featuredPlaceId = null;
      _rebuildViewModels();
    });
  }

  /// 내 여정에 담긴 장소의 방명록만 골라 방문 순서대로 정렬해 돌려준다.
  ///
  /// 서버 피드는 전체 장소를 주므로 여기서 여정 밖 장소를 걸러낸다.
  /// 장소별로 묶어 보여주려면 전체를 받아야 해서 페이지를 이어 부른다.
  Future<List<GuestbookFeedItem>> _fetchFeedForSchedule(
    ScheduleDetail? detail,
  ) async {
    if (detail == null) return const [];

    // place_id → 방문 순번
    final sorted = [...detail.places]
      ..sort(ScheduleDetail.compareByDayAndOrder);
    final order = <int, int>{};
    for (final p in sorted) {
      if (p.hasPlaceId) order.putIfAbsent(p.placeId, () => order.length);
    }
    if (order.isEmpty) return const [];

    final collected = <GuestbookFeedItem>[];
    var offset = 0;
    try {
      // 300건은 무한 루프와 과도한 요청을 막는 상한.
      while (collected.length < 300) {
        final page =
            await GuestbookApiService.fetchFeed(limit: 50, offset: offset);
        // 서버 피드는 전체 장소를 주므로 내 여정에 담긴 장소만 남긴다.
        // 그 외의 가공은 하지 않는다 — 서버가 내려준 건 그대로 보여준다.
        collected.addAll(
          page.items.where((e) => order.containsKey(e.place.id)),
        );
        if (!page.hasMore || page.items.isEmpty) break;
        offset = page.nextOffset;
      }
    } catch (e) {
      debugPrint('⚠️ [Guestbook] 피드 조회 실패: $e');
      return collected;
    }

    collected.sort((a, b) {
      final byPlace =
          (order[a.place.id] ?? 1 << 30).compareTo(order[b.place.id] ?? 1 << 30);
      if (byPlace != 0) return byPlace;
      return b.createdAt.compareTo(a.createdAt);
    });
    return collected;
  }

  /// 작성·삭제 뒤 피드만 다시 읽는다. 실패해도 조용히 넘어간다.
  Future<void> _reloadFeed() async {
    final feed = await _fetchFeedForSchedule(_schedule);
    if (!mounted) return;
    setState(() => _feed = feed);
  }

  /// 지금 화면에 보여줄 방명록. 장소를 고르면 그 장소만.
  List<GuestbookFeedItem> get _visibleFeed {
    final id = _selectedPlaceId;
    if (id == null) return _feed;
    return _feed.where((e) => e.place.id == id).toList();
  }

  /// 장소별 방명록 개수. 상단 칩에 표시.
  Map<int, int> get _feedCountByPlace {
    final counts = <int, int>{};
    for (final e in _feed) {
      counts[e.place.id] = (counts[e.place.id] ?? 0) + 1;
    }
    return counts;
  }

  /// 이 방명록이 내 것인지.
  ///
  /// `_books`에는 내 방명록만 들어 있으므로, 같은 장소의 내 방명록 id와
  /// 일치하면 그것만으로 확실하다. `/auth/me`가 실패해도 판별이 되도록
  /// 이 경로를 먼저 본다.
  bool _isMine(GuestbookFeedItem item) {
    final mine = _books[item.placeId];
    if (mine != null && mine.id == item.id) return true;
    return _myUserId != null && item.author.id == _myUserId;
  }

  /// 서버 원본(`_books`)에서 두 탭이 쓸 화면용 모델을 다시 만든다.
  /// setState 안에서만 호출할 것.
  void _rebuildViewModels() {
    final schedule = _schedule;

    final placeById = <int, SchedulePlace>{};
    if (schedule != null) {
      for (final p in schedule.places) {
        if (p.hasPlaceId) placeById.putIfAbsent(p.placeId, () => p);
      }
    }

    final memoryName = schedule?.memoryPlace?.name ?? '';
    final subtitle = memoryName.isNotEmpty
        ? '$memoryName 여정'
        : (schedule?.title ?? '지난 여정');

    final entries = <GuestbookEntry>[];
    final archive = <MemoryArchiveEntry>[];

    for (final book in _books.values) {
      final place = placeById[book.placeId];
      // GuestbookResponse에 장소 이름이 없어서 이번 여정 밖 장소는 이름을 못 채운다.
      final name = place?.title ?? '지난 여정의 장소';

      // 글이 있거나 사진이라도 올린 장소를 방명록 카드로 보여줌.
      if (book.hasContent || book.hasCurrentPhoto) {
        entries.add(GuestbookEntry.from(
          book,
          placeName: name,
          authorName: _authorName,
        ));
      }

      if (book.photos.isNotEmpty) {
        archive.add(MemoryArchiveEntry.from(
          book,
          placeName: name,
          subtitle: subtitle,
          placeImageUrl:
              (place != null && place.imageUrl.isNotEmpty) ? place.imageUrl : null,
        ));
      }
    }

    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    archive.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _entries = entries;
    _archive = archive;
  }

  /// 한 장소만 서버에서 다시 읽어 목록에 반영.
  Future<void> _refreshPlace(int placeId) async {
    final updated = await GuestbookApiService.fetchGuestbook(placeId);
    if (!mounted) return;
    setState(() {
      if (updated == null || updated.isEmpty) {
        _books.remove(placeId);
      } else {
        _books[placeId] = updated;
      }
      _rebuildViewModels();
    });
  }

  // ---------------------------------------------------------------------------
  // 작성 / 수정
  // ---------------------------------------------------------------------------

  /// 작성/수정 시트를 열고 결과를 서버에 반영함.
  Future<void> _openCompose({
    required _ComposeMode mode,
    int? placeId,
  }) async {
    if (_isSaving) return;

    final schedule = _schedule;
    if (schedule == null) {
      _toast('먼저 스케줄을 만들면 그 여정 기준으로 기억을 남길 수 있어요');
      return;
    }

    final options = _placeOptions(schedule);
    if (options.isEmpty) {
      // place_id가 없으면 방명록 API를 호출할 수 없음.
      _toast('이 여정의 장소 정보를 아직 불러오지 못했어요');
      return;
    }

    final result = await showModalBottomSheet<_ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        mode: mode,
        scheduleTitle: schedule.title,
        placeOptions: options,
        initialPlaceId: placeId ?? options.first.placeId,
        existingByPlaceId: Map.of(_books),
      ),
    );

    if (result == null || !mounted) return;
    await _applyCompose(result, mode);
  }

  /// 시트 결과를 서버 호출 순서에 맞춰 반영한다.
  ///
  /// 순서가 중요함: 방명록 행 확보 → CURRENT 업로드 → PAST 업로드.
  Future<void> _applyCompose(_ComposeResult result, _ComposeMode mode) async {
    setState(() => _isSaving = true);

    try {
      final placeId = result.placeId;
      final existing = _books[placeId];

      // 사진만 올리는 경우에도 방명록 레코드가 먼저 있어야 안전해서 한 번 만들어 둠.
      // photos 엔드포인트가 방명록을 자동 생성한다면 이 조건은 빼도 됨.
      if (result.noteChanged || existing == null) {
        await GuestbookApiService.saveContent(
          placeId,
          result.note.isEmpty ? null : result.note,
        );
      }

      if (result.currentPhotoPath != null) {
        await GuestbookApiService.uploadPhoto(
          placeId: placeId,
          type: ArchivePhotoType.current,
          filePath: result.currentPhotoPath!,
        );
        await PhotoService.instance.deleteSavedPhoto(result.currentPhotoPath);
      }

      if (result.pastPhotoPath != null) {
        await GuestbookApiService.uploadPhoto(
          placeId: placeId,
          type: ArchivePhotoType.past,
          filePath: result.pastPhotoPath!,
          takenYear: result.takenYear,
        );
        await PhotoService.instance.deleteSavedPhoto(result.pastPhotoPath);
      }

      await _refreshPlace(placeId);
      await _reloadFeed();

      if (!mounted) return;
      setState(() {
        _tabIndex = mode == _ComposeMode.guestbook ? 0 : 1;
        if (mode == _ComposeMode.archive) _featuredPlaceId = placeId;
      });
    } on GuestbookApiException catch (e) {
      // 사진 두 장 중 한 장만 올라간 상태일 수 있어 현재 상태를 다시 읽어둔다.
      await _silentRefresh(result.placeId);
      if (!mounted) return;
      _toast(e.userMessage);
    } catch (_) {
      await _silentRefresh(result.placeId);
      if (!mounted) return;
      _toast('저장하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 실패 복구용. 여기서 또 던지면 원래 에러 메시지를 덮어버려서 조용히 삼킴.
  Future<void> _silentRefresh(int placeId) async {
    try {
      await _refreshPlace(placeId);
    } catch (_) {}
  }

  /// 방명록을 통째로 지운다. 서버가 딸린 사진 레코드까지 함께 삭제한다.
  ///
  /// 삭제 키가 place_id가 아니라 guestbook_id라 둘 다 받는다.
  /// (place_id는 지운 뒤 그 장소만 다시 읽는 데 쓴다)
  Future<void> _confirmDeleteGuestbook({
    required int guestbookId,
    required int placeId,
  }) async {
    final hasPhotos = _books[placeId]?.photos.isNotEmpty ?? false;

    final ok = await _confirm(
      hasPhotos
          ? '이 방명록을 지울까요?\n올린 사진도 함께 삭제돼요.'
          : '이 방명록을 지울까요?',
    );
    if (!ok || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await GuestbookApiService.deleteGuestbook(guestbookId);
      await _refreshPlace(placeId);
      await _reloadFeed();
    } on GuestbookApiException catch (e) {
      if (mounted) _toast(e.userMessage);
    } catch (_) {
      if (mounted) _toast('지우지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 신고 / 차단
  // ---------------------------------------------------------------------------

  /// 남의 글에서 뜨는 메뉴. 공개되는 사용자 생성 콘텐츠라 Play 정책상 필요하다.
  Future<void> _openModerationMenu(GuestbookFeedItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModerationSheet(authorName: item.author.displayName),
    );
    if (action == null || !mounted) return;

    if (action == 'report') {
      final reported = await ReportSheet.show(
        context,
        guestbookId: item.id,
        authorName: item.author.displayName,
      );
      if (reported == true) _toast('신고가 접수됐어요. 운영자가 확인 후 조치합니다.');
    } else if (action == 'block') {
      await _confirmBlock(item);
    }
  }

  Future<void> _confirmBlock(GuestbookFeedItem item) async {
    final name = item.author.displayName;
    final ok = await _confirm(
      '$name님을 차단할까요?\n이 사용자의 방명록이 더 이상 보이지 않아요.',
      confirmLabel: '차단',
    );
    if (!ok || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await ModerationApiService.blockUser(item.author.id);
      if (!mounted) return;
      // 서버도 다음 요청부터 걸러주지만 기다리지 않고 화면에서 먼저 지운다.
      setState(() => _feed.removeWhere((e) => e.author.id == item.author.id));
      _toast('$name님을 차단했어요.');
    } on ModerationApiException catch (e) {
      if (mounted) _toast(e.userMessage);
    } catch (_) {
      if (mounted) _toast('차단하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openBlockedUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
    );
    // 차단을 풀고 돌아오면 그 사람 글이 다시 보여야 한다.
    if (mounted) _reloadFeed();
  }

  Future<bool> _confirm(String message, {String confirmLabel = '삭제'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        content: Text(message, style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // 데이터 헬퍼
  // ---------------------------------------------------------------------------

  /// 방명록을 남길 수 있는 장소만(place_id가 있는 것) 방문 순서대로, 중복 제거.
  List<_PlaceOption> _placeOptions(ScheduleDetail schedule) {
    final sorted = [...schedule.places]
      ..sort(ScheduleDetail.compareByDayAndOrder);

    final seen = <int>{};
    final options = <_PlaceOption>[];
    for (final p in sorted) {
      if (!p.hasPlaceId || p.title.isEmpty || !seen.add(p.placeId)) continue;
      options.add(_PlaceOption(placeId: p.placeId, name: p.title));
    }
    return options;
  }

  MemoryArchiveEntry? _archiveFor(int placeId) {
    for (final a in _archive) {
      if (a.placeId == placeId) return a;
    }
    return null;
  }

  /// 여정 장소를 방문 순서대로 늘어놓은 아카이브 슬롯 목록.
  List<_ArchiveSlot> _buildArchiveSlots(ScheduleDetail schedule) {
    final slots = <_ArchiveSlot>[];
    final used = <int>{};

    final sorted = [...schedule.places]
      ..sort(ScheduleDetail.compareByDayAndOrder);

    for (final p in sorted) {
      if (!p.hasPlaceId || p.title.isEmpty || !used.add(p.placeId)) continue;
      slots.add(_ArchiveSlot(
        placeId: p.placeId,
        placeName: p.title,
        placeImageUrl: p.imageUrl.isEmpty ? null : p.imageUrl,
        entry: _archiveFor(p.placeId),
      ));
    }

    // 여정에서 빠졌지만 사진을 올려둔 장소도 잃지 않게 뒤에 붙임.
    for (final a in _archive) {
      if (used.add(a.placeId)) {
        slots.add(_ArchiveSlot(
          placeId: a.placeId,
          placeName: a.placeName,
          placeImageUrl: a.placeImageUrl,
          entry: a,
        ));
      }
    }
    return slots;
  }

  void _goToScheduleTab() {
    AppShellController.instance.openHomeTab(context, tabIndex: 1);
  }

  // ---------------------------------------------------------------------------
  // 빌드
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              _GuestbookTopBar(
                addLabel: _tabIndex == 0 ? '방명록 남기기' : '그때-지금 사진 추가',
                onAddTap: () => _openCompose(
                  mode: _tabIndex == 0 ? _ComposeMode.guestbook : _ComposeMode.archive,
                ),
                onBlockedTap: _openBlockedUsers,
              ),
              _GuestbookTabs(
                index: _tabIndex,
                onChanged: (i) => setState(() => _tabIndex = i),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 1, color: AppColors.line),
              Expanded(child: _buildBody()),
            ],
          ),
          if (_isSaving) const _SavingOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    final schedule = _schedule;

    // 여정이 없어도 지난 방명록이 있으면 글 목록은 보여준다.
    if (schedule == null) {
      if (_tabIndex == 0 && _entries.isNotEmpty) return _buildMyEntriesList();
      return _EmptyStateCard(
        icon: _errorMessage == null ? Icons.map_outlined : Icons.cloud_off_outlined,
        title: _errorMessage == null ? '아직 만든 여정이 없어요' : '여정을 불러오지 못했어요',
        subtitle: _errorMessage ??
            '스케줄을 먼저 만들면 그 여정에 담긴 장소를 기준으로\n방명록과 그때-지금 사진을 남길 수 있어요',
        actionLabel: _errorMessage == null ? '스케줄 만들러 가기' : '다시 시도',
        onAction: _errorMessage == null ? _goToScheduleTab : _load,
      );
    }

    return Column(
      children: [
        if (_guestbookError != null)
          _InlineNotice(message: _guestbookError!, onRetry: _load),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: _JourneyBadge(
            title: schedule.title,
            placeCount: schedule.places.length,
          ),
        ),
        Expanded(
          child: _tabIndex == 0
              ? _buildGuestbookTab(schedule)
              : _buildArchiveTab(schedule),
        ),
      ],
    );
  }

  /// 여정을 못 불러왔을 때의 폴백. 장소 필터를 만들 수 없어 내 글만 보여준다.
  Widget _buildMyEntriesList() {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          10,
          AppSpacing.screenHorizontal,
          100,
        ),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, i) => _GuestbookEntryCard(
          entry: _entries[i],
          onEdit: () => _openCompose(
            mode: _ComposeMode.guestbook,
            placeId: _entries[i].placeId,
          ),
          onDelete: () => _confirmDeleteGuestbook(
            guestbookId: _entries[i].guestbookId,
            placeId: _entries[i].placeId,
          ),
        ),
      ),
    );
  }

  Widget _buildGuestbookTab(ScheduleDetail schedule) {
    final options = _placeOptions(schedule);
    final visible = _visibleFeed;

    return Column(
      children: [
        if (options.isNotEmpty)
          _PlaceFilterBar(
            options: options,
            counts: _feedCountByPlace,
            totalCount: _feed.length,
            selectedPlaceId: _selectedPlaceId,
            onChanged: (id) => setState(() => _selectedPlaceId = id),
          ),
        Expanded(
          child: visible.isEmpty
              ? _buildFeedEmptyState(schedule)
              : _buildFeedList(visible),
        ),
      ],
    );
  }

  Widget _buildFeedEmptyState(ScheduleDetail schedule) {
    final placeId = _selectedPlaceId;

    if (placeId != null) {
      final name = _placeNameOf(schedule, placeId);
      return _EmptyStateCard(
        icon: Icons.edit_note_outlined,
        title: '$name에 남긴 기억이 아직 없어요',
        subtitle: '이곳에서의 기억과 사진을\n첫 번째로 남겨보세요',
        actionLabel: '이 장소에 남기기',
        onAction: () =>
            _openCompose(mode: _ComposeMode.guestbook, placeId: placeId),
      );
    }

    return _EmptyStateCard(
      icon: Icons.edit_note_outlined,
      title: '아직 남긴 기억이 없어요',
      subtitle: '${schedule.title}에 담긴 장소를 골라\n그날의 기억과 사진을 남겨보세요',
      actionLabel: '첫 기억 남기기',
      onAction: () => _openCompose(mode: _ComposeMode.guestbook),
    );
  }

  Widget _buildFeedList(List<GuestbookFeedItem> items) {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          10,
          AppSpacing.screenHorizontal,
          100,
        ),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, i) {
          final item = items[i];
          final mine = _isMine(item);
          return _FeedEntryCard(
            item: item,
            isMine: mine,
            // 장소를 이미 골라놨으면 카드마다 같은 장소 태그가 반복돼 지저분하다.
            showPlaceTag: _selectedPlaceId == null,
            onEdit: mine
                ? () => _openCompose(
                      mode: _ComposeMode.guestbook,
                      placeId: item.placeId,
                    )
                : null,
            onDelete: mine
                ? () => _confirmDeleteGuestbook(
                      guestbookId: item.id,
                      placeId: item.placeId,
                    )
                : null,
            onModerate: mine ? null : () => _openModerationMenu(item),
          );
        },
      ),
    );
  }

  /// 여정에서 place_id로 장소 이름을 찾는다.
  String _placeNameOf(ScheduleDetail schedule, int placeId) {
    for (final p in schedule.places) {
      if (p.placeId == placeId && p.title.isNotEmpty) return p.title;
    }
    return '이 장소';
  }

  Widget _buildArchiveTab(ScheduleDetail schedule) {
    final slots = _buildArchiveSlots(schedule);

    if (slots.isEmpty) {
      return _EmptyStateCard(
        icon: Icons.photo_library_outlined,
        title: '이 여정에는 아직 장소가 없어요',
        subtitle: '스케줄에 장소가 담기면 그 장소의\n그때-지금 사진을 비교해볼 수 있어요',
        actionLabel: '스케줄 보러 가기',
        onAction: _goToScheduleTab,
      );
    }

    // 크게 볼 장소: 사용자가 고른 것 > 비교가 완성된 첫 장소 > 첫 장소
    _ArchiveSlot featured = slots.first;
    if (_featuredPlaceId != null) {
      for (final s in slots) {
        if (s.placeId == _featuredPlaceId) {
          featured = s;
          break;
        }
      }
    } else {
      for (final s in slots) {
        if (s.entry?.isComparable ?? false) {
          featured = s;
          break;
        }
      }
    }

    final others = slots.where((s) => s.placeId != featured.placeId).toList();
    final featuredEntry = featured.entry;

    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          14,
          AppSpacing.screenHorizontal,
          100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _archiveHint(featuredEntry),
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 6),
            Text(
              featured.placeName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.brandMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ..._buildFeatured(featured, featuredEntry),
            const SizedBox(height: AppSpacing.sectionGap),
            const Text(
              '다른 추억 둘러보기',
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle,
            ),
            const SizedBox(height: 12),
            if (others.isEmpty)
              const Text(
                '여정에 담긴 장소가 한 곳뿐이에요',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              )
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
                  final slot = others[i];
                  return _ArchiveGridCard(
                    slot: slot,
                    onTap: () {
                      if (slot.entry != null) {
                        setState(() => _featuredPlaceId = slot.placeId);
                      } else {
                        _openCompose(
                          mode: _ComposeMode.archive,
                          placeId: slot.placeId,
                        );
                      }
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _archiveHint(MemoryArchiveEntry? entry) {
    if (entry == null) {
      return '지금 모습을 찍고 예전 사진을 올리면\n좌우로 밀어 비교할 수 있어요.';
    }
    if (entry.needsPastPhoto) return '예전 사진을 더하면 지금과 비교할 수 있어요.';
    if (!entry.isComparable) return '지금 모습을 먼저 찍어주세요.';
    return '가운데 선을 좌우로 밀어 그때와 지금을 비교해보세요.';
  }

  List<Widget> _buildFeatured(_ArchiveSlot slot, MemoryArchiveEntry? entry) {
    if (entry == null) {
      return [
        _AddPhotoPrompt(
          placeName: slot.placeName,
          onTap: () => _openCompose(
            mode: _ComposeMode.archive,
            placeId: slot.placeId,
          ),
        ),
      ];
    }

    return [
      if (entry.isComparable)
        BeforeAfterSlider(
          beforeImage: entry.beforeImage,
          afterImage: entry.afterImage,
          beforeLabel: entry.beforeYear,
          afterLabel: entry.afterYear,
        )
      else
        _SinglePhotoCard(
          image: entry.afterImage ?? entry.beforeImage,
          label: entry.hasAfterPhoto ? entry.afterYear : entry.beforeYear,
        ),
      if (entry.isProcessing) ...[
        const SizedBox(height: 8),
        const _InlineNotice(message: '사진을 정리하는 중이에요. 잠시 뒤 아래로 당겨 새로고침해보세요.'),
      ],
      if (entry.note != null) ...[
        const SizedBox(height: 12),
        Text(entry.note!, textAlign: TextAlign.center, style: AppTextStyles.body),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _openCompose(
            mode: _ComposeMode.archive,
            placeId: slot.placeId,
          ),
          icon: Icon(
            entry.isComparable ? Icons.edit_outlined : Icons.add_a_photo_outlined,
            size: 16,
          ),
          label: Text(entry.isComparable ? '메모 수정하기' : '남은 사진 올리기'),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        '올린 사진은 아직 바꾸거나 지울 수 없어요',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall,
      ),
    ];
  }
}

/// 아카이브 한 칸. entry가 null이면 아직 사진이 없는 장소.
class _ArchiveSlot {
  final int placeId;
  final String placeName;
  final String? placeImageUrl;
  final MemoryArchiveEntry? entry;

  const _ArchiveSlot({
    required this.placeId,
    required this.placeName,
    this.placeImageUrl,
    this.entry,
  });
}

/// 장소 선택 칩 하나에 필요한 값.
class _PlaceOption {
  final int placeId;
  final String name;

  const _PlaceOption({required this.placeId, required this.name});
}

// =============================================================================
// 작성 시트
// =============================================================================

enum _ComposeMode { guestbook, archive }

class _ComposeResult {
  final int placeId;
  final String placeName;

  /// 방명록 텍스트. 아카이브 모드의 '메모'도 같은 필드로 저장됨.
  final String note;

  /// 텍스트가 실제로 바뀌었는지. 안 바뀌었으면 PUT을 건너뜀.
  final bool noteChanged;

  /// 새로 업로드할 '지금' 사진(CURRENT). 이미 서버에 있으면 null.
  final String? currentPhotoPath;

  /// 새로 업로드할 '그때' 사진(PAST). 이미 서버에 있으면 null.
  final String? pastPhotoPath;

  /// PAST 사진의 촬영 연도.
  final int? takenYear;

  const _ComposeResult({
    required this.placeId,
    required this.placeName,
    required this.note,
    required this.noteChanged,
    this.currentPhotoPath,
    this.pastPhotoPath,
    this.takenYear,
  });
}

/// 방명록/아카이브 작성 시트.
///
/// 서버가 CURRENT → PAST 순서를 요구해서 입력 순서도 '지금 → 그때'로 둔다.
/// 이미 올라간 사진은 교체 API가 없어 잠금 상태로만 보여준다.
class _ComposeSheet extends StatefulWidget {
  final _ComposeMode mode;
  final String scheduleTitle;
  final List<_PlaceOption> placeOptions;
  final int initialPlaceId;

  /// 장소별 현재 서버 상태. 장소를 바꾸면 이 맵에서 다시 읽는다.
  final Map<int, Guestbook> existingByPlaceId;

  const _ComposeSheet({
    required this.mode,
    required this.scheduleTitle,
    required this.placeOptions,
    required this.initialPlaceId,
    required this.existingByPlaceId,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();

  late int _placeId;

  /// 시트를 열었을 때의 서버 텍스트. 변경 여부 판단에 씀.
  String _originalNote = '';

  /// 새로 올릴 '지금' 사진 (CURRENT)
  String? _currentPhotoPath;

  /// 새로 올릴 '그때' 사진 (PAST)
  String? _pastPhotoPath;

  /// 어느 칸의 사진을 고르는 중인지.
  ArchivePhotoType? _pickingSlot;

  bool get _isArchive => widget.mode == _ComposeMode.archive;
  bool get _isPicking => _pickingSlot != null;

  Guestbook? get _existing => widget.existingByPlaceId[_placeId];

  bool get _hasServerCurrent => _existing?.hasCurrentPhoto ?? false;
  bool get _hasServerPast => _existing?.hasPastPhoto ?? false;

  /// 서버에 있든 방금 골랐든, 사진이 확보된 상태.
  bool get _hasCurrent => _hasServerCurrent || _currentPhotoPath != null;
  bool get _hasPast => _hasServerPast || _pastPhotoPath != null;

  @override
  void initState() {
    super.initState();
    _placeId = widget.initialPlaceId;
    _applyPlace(_placeId);
  }

  /// 장소가 바뀌면 그 장소의 서버 상태로 입력값을 다시 맞춘다.
  void _applyPlace(int placeId) {
    final book = widget.existingByPlaceId[placeId];
    _placeId = placeId;
    _originalNote = book?.content?.trim() ?? '';
    _noteCtrl.text = _originalNote;
    _currentPhotoPath = null;
    _pastPhotoPath = null;
    _yearCtrl.text = book?.pastPhoto?.takenYear?.toString() ?? '';
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  String get _placeName {
    for (final o in widget.placeOptions) {
      if (o.placeId == _placeId) return o.name;
    }
    return '';
  }

  Future<void> _pickPhoto(ArchivePhotoType type) async {
    if (_isPicking) return;

    final isNow = type == ArchivePhotoType.current;

    if (isNow ? _hasServerCurrent : _hasServerPast) {
      _toast('이미 올린 사진이에요. 교체는 아직 지원되지 않아요');
      return;
    }
    // 서버가 CURRENT 선행을 요구함.
    if (!isNow && !_hasCurrent) {
      _toast('지금 모습을 먼저 찍어주세요');
      return;
    }

    // '지금 사진'은 그 자리에서 찍은 것만 받음.
    ImageSource? source;
    if (!isNow) {
      source = await showPhotoSourceSheet(context);
      if (source == null || !mounted) return;
    }

    setState(() => _pickingSlot = type);
    String? picked;
    try {
      picked = isNow
          ? await PhotoService.instance.captureMemoryPhoto()
          : await PhotoService.instance.pickAndSaveMemoryPhoto(source: source!);
    } catch (_) {
      picked = null;
    }

    if (!mounted) return;
    setState(() {
      _pickingSlot = null;
      if (picked == null) return;
      if (isNow) {
        _currentPhotoPath = picked;
      } else {
        _pastPhotoPath = picked;
      }
    });

    if (picked == null) {
      _toast(isNow ? '카메라로 지금 모습을 찍어주세요' : '사진을 불러오지 못했어요');
    }
  }

  /// 로컬에만 있는 사진을 뺌. 서버에 올라간 사진은 대상이 아님.
  void _clearLocalPhoto(ArchivePhotoType type) {
    setState(() {
      if (type == ArchivePhotoType.current) {
        _currentPhotoPath = null;
        // 지금 사진이 빠지면 그때 사진도 올릴 수 없어 같이 비움.
        if (!_hasServerCurrent) _pastPhotoPath = null;
      } else {
        _pastPhotoPath = null;
      }
    });
  }

  void _submit() {
    final note = _noteCtrl.text.trim();

    if (_placeId <= 0) {
      _toast('장소를 선택해주세요');
      return;
    }

    if (_isArchive) {
      if (!_hasCurrent) {
        _toast('지금 모습을 카메라로 찍어주세요');
        return;
      }
      if (!_hasPast) {
        _toast('그때 사진을 올려주세요');
        return;
      }
    } else if (note.isEmpty && _currentPhotoPath == null && !_hasServerCurrent) {
      _toast('남길 기억이나 사진을 하나는 넣어주세요');
      return;
    }

    if (note.length > GuestbookApiService.maxContentLength) {
      _toast('방명록은 ${GuestbookApiService.maxContentLength}자까지 쓸 수 있어요');
      return;
    }

    int? takenYear;
    if (_pastPhotoPath != null) {
      final raw = _yearCtrl.text.trim();
      if (raw.isNotEmpty) {
        final parsed = int.tryParse(raw);
        if (parsed == null || parsed < 1900 || parsed > DateTime.now().year) {
          _toast('연도는 1900부터 ${DateTime.now().year} 사이로 적어주세요');
          return;
        }
        takenYear = parsed;
      }
    }

    Navigator.of(context).pop(
      _ComposeResult(
        placeId: _placeId,
        placeName: _placeName,
        note: note,
        noteChanged: note != _originalNote,
        currentPhotoPath: _currentPhotoPath,
        pastPhotoPath: _pastPhotoPath,
        takenYear: takenYear,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final existing = _existing;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardLarge)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            12,
            AppSpacing.screenHorizontal,
            AppSpacing.bottomBarBottom,
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
              Text(
                _isArchive ? '그때-지금 사진 남기기' : '방명록 남기기',
                style: AppTextStyles.screenTitle,
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.scheduleTitle} 여정 기준',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.brandMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),

              const _FieldLabel('장소'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in widget.placeOptions)
                    _SelectChip(
                      label: option.name,
                      selected: _placeId == option.placeId,
                      onTap: () => setState(() => _applyPlace(option.placeId)),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // 서버가 CURRENT 선행을 요구해서 '지금 사진'이 먼저 온다.
              _FieldLabel(
                _isArchive ? '지금 사진 (필수 · 카메라 촬영)' : '지금 사진 (선택 · 카메라 촬영)',
              ),
              const SizedBox(height: 8),
              _PhotoPickerBox(
                photoPath: _currentPhotoPath,
                uploadedUrl: existing?.currentPhoto?.displayUrl,
                isLoading: _pickingSlot == ArchivePhotoType.current,
                emptyLabel: '지금 모습을 카메라로 찍기',
                changeLabel: '다시 찍기',
                changeIcon: Icons.photo_camera_outlined,
                onTap: () => _pickPhoto(ArchivePhotoType.current),
                onClear: () => _clearLocalPhoto(ArchivePhotoType.current),
              ),

              if (_isArchive) ...[
                const SizedBox(height: 18),
                const _FieldLabel('그때 사진 (필수)'),
                const SizedBox(height: 8),
                _PhotoPickerBox(
                  photoPath: _pastPhotoPath,
                  uploadedUrl: existing?.pastPhoto?.displayUrl,
                  isLoading: _pickingSlot == ArchivePhotoType.past,
                  enabled: _hasCurrent,
                  emptyLabel: '예전에 찍은 사진 가져오기',
                  lockedLabel: '지금 사진을 먼저 올려주세요',
                  onTap: () => _pickPhoto(ArchivePhotoType.past),
                  onClear: () => _clearLocalPhoto(ArchivePhotoType.past),
                ),
                if (_pastPhotoPath != null) ...[
                  const SizedBox(height: 18),
                  const _FieldLabel('그때는 언제인가요 (선택)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                    style: AppTextStyles.input,
                    decoration: const InputDecoration(
                      hintText: '예: 1998',
                      hintStyle: AppTextStyles.inputHint,
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 18),
              _FieldLabel(_isArchive ? '메모 (선택)' : '기억'),
              if (_isArchive) ...[
                const SizedBox(height: 4),
                const Text(
                  '방명록 탭의 글과 같은 내용이에요',
                  style: AppTextStyles.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                style: AppTextStyles.input,
                maxLines: 4,
                maxLength: GuestbookApiService.maxContentLength,
                decoration: InputDecoration(
                  hintText: _isArchive
                      ? '이 사진에 얽힌 이야기를 적어보세요'
                      : '이 장소에서의 기억을 자유롭게 남겨보세요',
                  hintStyle: AppTextStyles.inputHint,
                ),
              ),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isPicking ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    existing == null ? '등록하기' : '저장하기',
                    style: AppTextStyles.button,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// 장소 선택용 칩.
class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.accent : AppColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: selected ? AppColors.accent : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 사진을 고르는 영역.
///
/// [uploadedUrl]이 있으면 이미 서버에 올라간 사진이라 바꾸거나 뺄 수 없다.
class _PhotoPickerBox extends StatelessWidget {
  final String? photoPath;
  final String? uploadedUrl;
  final bool isLoading;
  final String emptyLabel;
  final String changeLabel;
  final IconData changeIcon;
  final VoidCallback onTap;
  final VoidCallback onClear;

  /// false면 아직 고를 수 없는 상태(잠금)로 흐리게 보여줌.
  final bool enabled;
  final String? lockedLabel;

  const _PhotoPickerBox({
    required this.photoPath,
    required this.isLoading,
    required this.emptyLabel,
    required this.onTap,
    required this.onClear,
    this.uploadedUrl,
    this.changeLabel = '다른 사진',
    this.changeIcon = Icons.autorenew,
    this.enabled = true,
    this.lockedLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: const CircularProgressIndicator(color: AppColors.accent),
      );
    }

    // 이미 서버에 올라간 사진 — 보기만 가능.
    final uploaded = uploadedUrl;
    if (uploaded != null && uploaded.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Image.network(
              uploaded,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _photoFallback('사진을 열 수 없어요'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(
                '이미 올린 사진이에요',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      );
    }

    final path = photoPath;
    if (path == null) {
      final locked = !enabled;
      return GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: locked ? 0.45 : 1,
          child: Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: locked ? AppColors.line : AppColors.lineAccent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  locked
                      ? Icons.lock_outline
                      : (changeIcon == Icons.photo_camera_outlined
                          ? Icons.photo_camera_outlined
                          : Icons.add_a_photo_outlined),
                  color: AppColors.brandMuted,
                  size: 26,
                ),
                const SizedBox(height: 8),
                Text(
                  locked ? (lockedLabel ?? emptyLabel) : emptyLabel,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.file(
            File(path),
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _photoFallback('사진을 열 수 없어요'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: onTap,
              icon: Icon(changeIcon, size: 16, color: AppColors.accent),
              label: Text(
                changeLabel,
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: onClear,
              child: const Text('사진 빼기', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _photoFallback(String message) => Container(
        height: 180,
        alignment: Alignment.center,
        color: AppColors.background,
        child: Text(message, style: AppTextStyles.bodySmall),
      );
}

// =============================================================================
// 화면 조각들
// =============================================================================

/// 저장/업로드 중 입력을 막는 오버레이.
class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: AppColors.background.withValues(alpha: 0.72),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.accent),
                SizedBox(height: 12),
                Text('저장하는 중이에요', style: AppTextStyles.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 목록 위에 얇게 깔리는 안내 줄. 부분 실패를 알리되 화면은 막지 않음.
class _InlineNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _InlineNotice({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        10,
        AppSpacing.screenHorizontal,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppTextStyles.bodySmall)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '다시 시도',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// 사진이 한 장만 있을 때 쓰는 단독 표시.
class _SinglePhotoCard extends StatelessWidget {
  final ImageProvider? image;
  final String label;

  const _SinglePhotoCard({required this.image, required this.label});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MemoryPhotoHero(
          image: image,
          height: 260,
          borderRadius: BorderRadius.circular(AppRadius.cardHero),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.cardBackground.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// 화면 상단 - 타이틀 + 차단 목록 / 새 글 작성 버튼.
class _GuestbookTopBar extends StatelessWidget {
  final VoidCallback onAddTap;
  final String addLabel;

  /// 차단한 사용자 관리 화면으로 이동.
  final VoidCallback onBlockedTap;

  const _GuestbookTopBar({
    required this.onAddTap,
    required this.addLabel,
    required this.onBlockedTap,
  });

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
          Text('방명록', style: AppTextStyles.heroGreeting),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: '차단한 사용자',
                child: GestureDetector(
                  onTap: onBlockedTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Icon(Icons.block,
                        color: AppColors.text, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: addLabel,
                child: GestureDetector(
                  onTap: onAddTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      boxShadow: AppShadows.fab,
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.cardBackground, size: 20),
                  ),
                ),
              ),
            ],
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

/// 지금 어떤 여정 기준으로 보고 있는지 알려주는 배지.
class _JourneyBadge extends StatelessWidget {
  final String title;
  final int placeCount;

  const _JourneyBadge({required this.title, required this.placeCount});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.brandLight.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined,
                size: AppIconSize.inCardSmall, color: AppColors.text),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$title 여정 기준 · $placeCount곳',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.brandMuted),
            const SizedBox(height: 14),
            Text(title, style: AppTextStyles.cardTitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.button),
                ),
                elevation: 0,
              ),
              child: Text(actionLabel, style: AppTextStyles.button),
            ),
          ],
        ),
      ),
    );
  }
}

/// 방명록 탭 상단의 장소 선택 줄.
///
/// 여정에 담긴 장소를 방문 순서대로 늘어놓고, 고른 장소의 방명록만 보여준다.
class _PlaceFilterBar extends StatelessWidget {
  final List<_PlaceOption> options;
  final Map<int, int> counts;
  final int totalCount;
  final int? selectedPlaceId;
  final ValueChanged<int?> onChanged;

  const _PlaceFilterBar({
    required this.options,
    required this.counts,
    required this.totalCount,
    required this.selectedPlaceId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenHorizontal,
          vertical: 4,
        ),
        children: [
          _FilterChip(
            label: '전체',
            count: totalCount,
            selected: selectedPlaceId == null,
            onTap: () => onChanged(null),
          ),
          for (final o in options) ...[
            const SizedBox(width: 7),
            _FilterChip(
              label: o.name,
              count: counts[o.placeId] ?? 0,
              selected: selectedPlaceId == o.placeId,
              onTap: () => onChanged(o.placeId),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? AppColors.cardBackground
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: AppTextStyles.caption.copyWith(
                  color: selected
                      ? AppColors.cardBackground.withValues(alpha: 0.85)
                      : AppColors.brandMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 방명록 카드. 내 글이면 수정·삭제, 남의 글이면 신고·차단 메뉴가 붙는다.
class _FeedEntryCard extends StatelessWidget {
  final GuestbookFeedItem item;
  final bool isMine;
  final bool showPlaceTag;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onModerate;

  const _FeedEntryCard({
    required this.item,
    required this.isMine,
    required this.showPlaceTag,
    this.onEdit,
    this.onDelete,
    this.onModerate,
  });

  @override
  Widget build(BuildContext context) {
    final photo = item.coverPhoto;

    return GestureDetector(
      onLongPress: onEdit,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPaddingLarge),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AuthorAvatar(name: item.author.displayName),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.author.displayName,
                          style: AppTextStyles.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentLight,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '내 글',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(_relativeDate(item.createdAt),
                    style: AppTextStyles.caption),
                if (isMine && onEdit != null && onDelete != null)
                  _EntryMenuButton(onEdit: onEdit!, onDelete: onDelete!)
                else if (onModerate != null)
                  IconButton(
                    tooltip: '신고 / 차단',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_horiz,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: onModerate,
                  ),
              ],
            ),
            if (photo != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.thumbnail),
                child: Image.network(
                  photo.displayUrl,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 170,
                    alignment: Alignment.center,
                    color: AppColors.background,
                    child: const Text('사진을 열 수 없어요',
                        style: AppTextStyles.bodySmall),
                  ),
                ),
              ),
            ],
            if (item.hasContent) ...[
              const SizedBox(height: 10),
              Text(
                item.content!,
                style: AppTextStyles.body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (showPlaceTag) ...[
              const SizedBox(height: 10),
              _PlaceTag(label: item.place.name),
            ],
          ],
        ),
      ),
    );
  }

  /// GuestbookEntry의 relativeDate와 같은 규칙.
  String _relativeDate(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${at.year}.${at.month.toString().padLeft(2, '0')}.'
        '${at.day.toString().padLeft(2, '0')}';
  }
}

/// 남의 글 ⋯ 메뉴 - 신고 / 차단.
class _ModerationSheet extends StatelessWidget {
  final String authorName;
  const _ModerationSheet({required this.authorName});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.cardHero)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            ListTile(
              leading: const Icon(Icons.flag_outlined,
                  size: 20, color: AppColors.text),
              title: const Text('신고하기', style: AppTextStyles.body),
              subtitle: Text(
                '부적절한 내용을 운영자에게 알립니다',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.of(context).pop('report'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.block, size: 20, color: AppColors.text),
              title: Text('$authorName님 차단하기', style: AppTextStyles.body),
              subtitle: Text(
                '이 사용자의 방명록이 보이지 않게 됩니다',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
              ),
              onTap: () => Navigator.of(context).pop('block'),
            ),
            const SizedBox(height: AppSpacing.cardGap),
          ],
        ),
      ),
    );
  }
}

class _GuestbookEntryCard extends StatelessWidget {
  final GuestbookEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GuestbookEntryCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onEdit,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPaddingLarge),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
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
                _EntryMenuButton(onEdit: onEdit, onDelete: onDelete),
              ],
            ),
            if (entry.hasPhoto) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.thumbnail),
                child: Image(
                  image: entry.image!,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 170,
                    alignment: Alignment.center,
                    color: AppColors.background,
                    child: const Text('사진을 열 수 없어요', style: AppTextStyles.bodySmall),
                  ),
                ),
              ),
            ],
            if (entry.content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                entry.content,
                style: AppTextStyles.body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            _PlaceTag(label: entry.placeName),
          ],
        ),
      ),
    );
  }
}

/// 카드 오른쪽 위 ⋮ 메뉴 - 수정 / 삭제.
class _EntryMenuButton extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EntryMenuButton({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '수정 / 삭제',
      padding: EdgeInsets.zero,
      color: AppColors.cardBackground,
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: AppColors.text),
              SizedBox(width: 8),
              Text('수정하기', style: AppTextStyles.body),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Text(
                '글 지우기',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 작성자 이름을 그대로 보여주는 동그란 아바타.
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
        ),
      ),
    );
  }
}

/// 카드 하단의 장소 태그 pill.
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
          const Icon(Icons.place_outlined,
              size: AppIconSize.inCardSmall, color: AppColors.accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사진이 없는 장소에 추가를 유도하는 카드.
class _AddPhotoPrompt extends StatelessWidget {
  final String placeName;
  final VoidCallback onTap;

  const _AddPhotoPrompt({required this.placeName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.cardHero),
          border: Border.all(color: AppColors.lineAccent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_a_photo_outlined, size: 32, color: AppColors.brandMuted),
            const SizedBox(height: 10),
            Text(
              '$placeName의 그때-지금 사진 올리기',
              style: AppTextStyles.cardTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              '지금 모습을 카메라로 찍고 예전 사진을 올리면\n좌우로 밀어 비교할 수 있어요',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveGridCard extends StatelessWidget {
  final _ArchiveSlot slot;
  final VoidCallback onTap;

  const _ArchiveGridCard({required this.slot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entry = slot.entry;
    final hasPhoto = entry?.hasBeforePhoto ?? false;
    final url = slot.placeImageUrl;
    final ImageProvider? cover = entry?.beforeImage ??
        entry?.afterImage ??
        ((url != null && url.isNotEmpty) ? NetworkImage(url) : null);

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
              image: cover,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            // 아래 텍스트가 사진에 묻히지 않게 깔아둔 스크림.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.cardBackground.withValues(alpha: 0),
                      AppColors.cardBackground.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
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
                    slot.placeName,
                    style: AppTextStyles.cardTitle.copyWith(color: AppColors.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto ? '눌러서 비교해보기' : '눌러서 그때-지금 사진 올리기',
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!hasPhoto)
              const Positioned(
                right: 8,
                top: 8,
                child: Icon(Icons.add_circle, size: 22, color: AppColors.accent),
              ),
          ],
        ),
      ),
    );
  }
}
