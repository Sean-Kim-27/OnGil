import 'dart:io';

import 'package:flutter/material.dart';

import '../controllers/app_shell_controller.dart';
import '../models/guestbook_entry.dart';
import '../models/memory_archive_entry.dart';
import '../models/schedule.dart';
import '../services/auth_service.dart';
import '../services/guestbook_service.dart';
import '../services/photo_service.dart';
import '../services/schedule_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/before_after_slider.dart';
import '../widgets/memory_photo.dart';
import '../widgets/photo_source_sheet.dart';

/// 방명록 화면. '방명록'(글 목록) / '아카이브'(그때-지금 사진 비교) 두 탭.
///
/// 마지막으로 만든 여정을 기준으로 동작하고, 작성물은 기기에 저장됨.
class GuestbookScreen extends StatefulWidget {
  const GuestbookScreen({super.key});

  @override
  State<GuestbookScreen> createState() => _GuestbookScreenState();
}

class _GuestbookScreenState extends State<GuestbookScreen> {
  int _tabIndex = 0; // 0: 방명록, 1: 아카이브

  bool _isLoading = true;

  /// 여정을 불러오지 못했을 때의 안내 문구.
  String? _errorMessage;

  ScheduleDetail? _schedule;
  String _authorName = '나';

  List<GuestbookEntry> _entries = [];
  List<MemoryArchiveEntry> _archive = [];

  /// 아카이브 탭에서 크게 비교 중인 장소 이름.
  String? _featuredPlaceName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 마지막 여정 + 그 여정에 남긴 방명록/아카이브를 한 번에 불러옴.
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final nickname = await AuthService.instance.getNickname();
    final scheduleId = await ScheduleApiService.getLastScheduleId();

    if (scheduleId == null) {
      if (!mounted) return;
      setState(() {
        _schedule = null;
        _entries = [];
        _archive = [];
        _authorName = (nickname == null || nickname.isEmpty) ? '나' : nickname;
        _isLoading = false;
      });
      return;
    }

    ScheduleDetail? detail;
    String? error;
    try {
      detail = await ScheduleApiService.fetchScheduleDetail(scheduleId);
    } on ScheduleApiException catch (e) {
      error = e.userMessage;
    } catch (_) {
      error = '여정을 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
    }

    // 여정 조회가 실패해도 저장해둔 기억은 보여줄 수 있으므로 같이 읽음.
    final entries = await GuestbookService.instance.loadEntries(scheduleId);
    final archive = await GuestbookService.instance.loadArchive(scheduleId);

    if (!mounted) return;
    setState(() {
      _schedule = detail;
      _entries = entries;
      _archive = archive;
      _errorMessage = error;
      _authorName = (nickname == null || nickname.isEmpty) ? '나' : nickname;
      _isLoading = false;
      _featuredPlaceName = null;
    });
  }

  // ---------------------------------------------------------------------------
  // 작성
  // ---------------------------------------------------------------------------

  /// 작성/수정 시트를 열고 결과를 받아 저장함.
  Future<void> _openCompose({
    required _ComposeMode mode,
    String? initialPlaceName,
    GuestbookEntry? editEntry,
    MemoryArchiveEntry? editArchive,
  }) async {
    final schedule = _schedule;
    if (schedule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 스케줄을 만들면 그 여정 기준으로 기억을 남길 수 있어요')),
      );
      return;
    }

    final savedYear = editArchive?.beforeYear;
    final result = await showModalBottomSheet<_ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComposeSheet(
        mode: mode,
        scheduleTitle: schedule.title,
        placeNames: _placeNames(schedule),
        initialPlaceName:
            initialPlaceName ?? editEntry?.placeName ?? editArchive?.placeName,
        initialNote: editEntry?.content ?? editArchive?.note,
        initialPhotoPath: editEntry?.photoPath ?? editArchive?.beforePhotoPath,
        initialAfterPhotoPath: editArchive?.afterPhotoPath,
        // '그때'는 연도 미입력 시의 기본 표기라 입력칸엔 채우지 않음.
        initialYear: (savedYear == null || savedYear == '그때') ? null : savedYear,
        isEditing: editEntry != null || editArchive != null,
      ),
    );

    if (result == null || !mounted) return;

    if (mode == _ComposeMode.guestbook) {
      await _saveGuestbook(schedule, result, editEntry);
    } else {
      await _saveArchive(schedule, result, editArchive);
    }
  }

  Future<void> _saveGuestbook(
    ScheduleDetail schedule,
    _ComposeResult result,
    GuestbookEntry? editEntry,
  ) async {
    if (editEntry != null) {
      final updated = editEntry.copyWith(
        placeName: result.placeName,
        content: result.note,
        photoPath: result.photoPath,
        clearPhoto: result.photoPath == null,
      );
      await GuestbookService.instance.updateEntry(updated);
      // 바뀐 사진 파일 정리.
      if (editEntry.photoPath != null && editEntry.photoPath != updated.photoPath) {
        await PhotoService.instance.deleteSavedPhoto(editEntry.photoPath);
      }
      if (!mounted) return;
      setState(() {
        final i = _entries.indexWhere((e) => e.id == updated.id);
        if (i >= 0) _entries[i] = updated;
        _tabIndex = 0;
      });
      return;
    }

    final entry = GuestbookEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      scheduleId: schedule.id,
      placeName: result.placeName,
      authorName: _authorName,
      content: result.note,
      createdAt: DateTime.now(),
      photoPath: result.photoPath,
    );
    await GuestbookService.instance.addEntry(entry);
    if (!mounted) return;
    setState(() {
      _entries.insert(0, entry);
      _tabIndex = 0;
    });
  }

  Future<void> _saveArchive(
    ScheduleDetail schedule,
    _ComposeResult result,
    MemoryArchiveEntry? editArchive,
  ) async {
    final matched = _findPlace(schedule, result.placeName);
    final memoryName = schedule.memoryPlace?.name ?? '';
    final placeImage =
        (matched != null && matched.imageUrl.isNotEmpty) ? matched.imageUrl : null;

    final entry = MemoryArchiveEntry(
      id: editArchive?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      scheduleId: schedule.id,
      placeName: result.placeName,
      subtitle: memoryName.isNotEmpty ? '$memoryName 여정' : schedule.title,
      beforeYear: result.beforeYear.isEmpty ? '그때' : result.beforeYear,
      afterYear: '지금',
      beforePhotoPath: result.photoPath,
      afterPhotoPath: result.afterPhotoPath,
      afterImageUrl: placeImage,
      note: result.note.isEmpty ? null : result.note,
      createdAt: editArchive?.createdAt ?? DateTime.now(),
    );

    if (editArchive != null) {
      await GuestbookService.instance.updateArchive(entry);
      // 교체된 사진 파일 정리
      if (editArchive.beforePhotoPath != entry.beforePhotoPath) {
        await PhotoService.instance.deleteSavedPhoto(editArchive.beforePhotoPath);
      }
      if (editArchive.afterPhotoPath != entry.afterPhotoPath) {
        await PhotoService.instance.deleteSavedPhoto(editArchive.afterPhotoPath);
      }
    } else {
      await GuestbookService.instance.addArchive(entry);
    }

    if (!mounted) return;
    setState(() {
      _archive.removeWhere((a) => a.id == entry.id || a.placeName == entry.placeName);
      _archive.insert(0, entry);
      _tabIndex = 1;
      _featuredPlaceName = entry.placeName;
    });
  }

  Future<void> _confirmDeleteEntry(GuestbookEntry entry) async {
    final ok = await _confirm('이 방명록을 지울까요?');
    if (!ok || !mounted) return;
    await GuestbookService.instance.removeEntry(entry.id);
    await PhotoService.instance.deleteSavedPhoto(entry.photoPath);
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
  }

  Future<void> _confirmDeleteArchive(MemoryArchiveEntry entry) async {
    final ok = await _confirm('이 장소의 그때 사진을 지울까요?');
    if (!ok || !mounted) return;
    await GuestbookService.instance.removeArchive(entry.id);
    await PhotoService.instance.deleteSavedPhoto(entry.beforePhotoPath);
    await PhotoService.instance.deleteSavedPhoto(entry.afterPhotoPath);
    if (!mounted) return;
    setState(() {
      _archive.removeWhere((a) => a.id == entry.id);
      if (_featuredPlaceName == entry.placeName) _featuredPlaceName = null;
    });
  }

  Future<bool> _confirm(String message) async {
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
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // 데이터 헬퍼
  // ---------------------------------------------------------------------------

  /// 여정에 담긴 장소 이름 목록(방문 순서, 중복 제거).
  List<String> _placeNames(ScheduleDetail schedule) {
    final sorted = [...schedule.places]
      ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder));
    final seen = <String>{};
    final names = <String>[];
    for (final p in sorted) {
      if (p.title.isEmpty || !seen.add(p.title)) continue;
      names.add(p.title);
    }
    return names;
  }

  SchedulePlace? _findPlace(ScheduleDetail schedule, String title) {
    for (final p in schedule.places) {
      if (p.title == title) return p;
    }
    return null;
  }

  MemoryArchiveEntry? _archiveFor(String placeName) {
    for (final a in _archive) {
      if (a.placeName == placeName) return a;
    }
    return null;
  }

  /// 여정 장소를 방문 순서대로 늘어놓은 아카이브 슬롯 목록.
  List<_ArchiveSlot> _buildArchiveSlots(ScheduleDetail schedule) {
    final slots = <_ArchiveSlot>[];
    final used = <String>{};

    final sorted = [...schedule.places]
      ..sort((a, b) => a.visitOrder.compareTo(b.visitOrder));

    for (final p in sorted) {
      if (p.title.isEmpty || !used.add(p.title)) continue;
      slots.add(_ArchiveSlot(
        placeName: p.title,
        afterImageUrl: p.imageUrl.isEmpty ? null : p.imageUrl,
        entry: _archiveFor(p.title),
      ));
    }

    // 여정에서 빠졌지만 사진을 올려둔 장소도 잃지 않게 뒤에 붙임.
    for (final a in _archive) {
      if (used.add(a.placeName)) {
        slots.add(_ArchiveSlot(
          placeName: a.placeName,
          afterImageUrl: a.afterImageUrl,
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
      child: Column(
        children: [
          _GuestbookTopBar(
            addLabel: _tabIndex == 0 ? '방명록 남기기' : '그때 사진 추가',
            onAddTap: () => _openCompose(
              mode: _tabIndex == 0 ? _ComposeMode.guestbook : _ComposeMode.archive,
            ),
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
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    final schedule = _schedule;

    if (schedule == null) {
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

  Widget _buildGuestbookTab(ScheduleDetail schedule) {
    if (_entries.isEmpty) {
      return _EmptyStateCard(
        icon: Icons.edit_note_outlined,
        title: '이 여정에 남긴 기억이 아직 없어요',
        subtitle: '${schedule.title}에 담긴 장소를 골라\n그날의 기억과 사진을 남겨보세요',
        actionLabel: '첫 기억 남기기',
        onAction: () => _openCompose(mode: _ComposeMode.guestbook),
      );
    }

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
            editEntry: _entries[i],
          ),
          onDelete: () => _confirmDeleteEntry(_entries[i]),
        ),
      ),
    );
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

    // 크게 볼 장소: 사용자가 고른 것 > 사진이 올라간 첫 장소 > 첫 장소
    _ArchiveSlot featured = slots.first;
    if (_featuredPlaceName != null) {
      for (final s in slots) {
        if (s.placeName == _featuredPlaceName) {
          featured = s;
          break;
        }
      }
    } else {
      for (final s in slots) {
        if (s.entry != null) {
          featured = s;
          break;
        }
      }
    }

    final others = slots.where((s) => s.placeName != featured.placeName).toList();
    final featuredEntry = featured.entry;

    return SingleChildScrollView(
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
            featuredEntry != null
                ? '가운데 선을 좌우로 밀어 그때와 지금을 비교해보세요.'
                : '그때 사진과 지금 사진을 함께 올리면 비교할 수 있어요.',
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

          if (featuredEntry != null) ...[
            BeforeAfterSlider(
              beforeImage: featuredEntry.beforeImage,
              afterImage: featuredEntry.afterImage,
              beforeLabel: featuredEntry.beforeYear,
              afterLabel: featuredEntry.afterYear,
            ),
            if (featuredEntry.note != null) ...[
              const SizedBox(height: 12),
              Text(
                featuredEntry.note!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCompose(
                      mode: _ComposeMode.archive,
                      editArchive: featuredEntry,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('수정하기'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _confirmDeleteArchive(featuredEntry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                  ),
                  child: const Text('삭제'),
                ),
              ],
            ),
          ] else
            _AddPhotoPrompt(
              placeName: featured.placeName,
              onTap: () => _openCompose(
                mode: _ComposeMode.archive,
                initialPlaceName: featured.placeName,
              ),
            ),

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
                      setState(() => _featuredPlaceName = slot.placeName);
                    } else {
                      _openCompose(
                        mode: _ComposeMode.archive,
                        initialPlaceName: slot.placeName,
                      );
                    }
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

/// 아카이브 한 칸. entry가 null이면 아직 사진이 없는 장소.
class _ArchiveSlot {
  final String placeName;
  final String? afterImageUrl;
  final MemoryArchiveEntry? entry;

  const _ArchiveSlot({
    required this.placeName,
    this.afterImageUrl,
    this.entry,
  });
}

// =============================================================================
// 작성 시트
// =============================================================================

enum _ComposeMode { guestbook, archive }

class _ComposeResult {
  final String placeName;
  final String note;

  /// 방명록이면 첨부 사진, 아카이브면 '그때' 사진.
  final String? photoPath;

  /// 아카이브의 '지금' 사진. 아카이브에서는 필수.
  final String? afterPhotoPath;

  final String beforeYear;

  const _ComposeResult({
    required this.placeName,
    required this.note,
    this.photoPath,
    this.afterPhotoPath,
    this.beforeYear = '',
  });
}

/// 방명록/아카이브 작성 시트. 컨트롤러를 자기 State에서 만들고 dispose까지 책임짐.
class _ComposeSheet extends StatefulWidget {
  final _ComposeMode mode;
  final String scheduleTitle;
  final List<String> placeNames;
  final String? initialPlaceName;

  // '수정'으로 열었을 때 채워넣을 기존 값들.
  final String? initialNote;
  final String? initialPhotoPath;
  final String? initialAfterPhotoPath;
  final String? initialYear;
  final bool isEditing;

  const _ComposeSheet({
    required this.mode,
    required this.scheduleTitle,
    required this.placeNames,
    this.initialPlaceName,
    this.initialNote,
    this.initialPhotoPath,
    this.initialAfterPhotoPath,
    this.initialYear,
    this.isEditing = false,
  });

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _customPlaceCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();

  String? _selectedPlace;
  bool _useCustomPlace = false;

  /// 방명록 첨부 사진 / 아카이브의 '그때' 사진
  String? _photoPath;

  /// 아카이브의 '지금' 사진
  String? _afterPhotoPath;

  /// 어느 칸의 사진을 고르는 중인지.
  _PhotoSlot? _pickingSlot;

  bool get _isArchive => widget.mode == _ComposeMode.archive;
  bool get _isPicking => _pickingSlot != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPlaceName;
    if (initial != null && widget.placeNames.contains(initial)) {
      _selectedPlace = initial;
    } else if (widget.placeNames.isNotEmpty) {
      _selectedPlace = widget.placeNames.first;
    } else {
      // 여정에 장소가 없으면 직접 입력만 가능.
      _useCustomPlace = true;
      if (initial != null) _customPlaceCtrl.text = initial;
    }

    _noteCtrl.text = widget.initialNote ?? '';
    _yearCtrl.text = widget.initialYear ?? '';
    _photoPath = widget.initialPhotoPath;
    _afterPhotoPath = widget.initialAfterPhotoPath;
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _customPlaceCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(_PhotoSlot slot) async {
    if (_isPicking) return;

    // '지금 사진'은 앨범에서 고를 수 없고 그 자리에서 찍은 것만 받음.
    final isNowPhoto = slot == _PhotoSlot.after;

    // 그때 사진이 먼저 올라와 있어야 지금 사진을 찍을 수 있음.
    if (isNowPhoto && _photoPath == null) {
      _toast('그때 사진을 먼저 올려주세요');
      return;
    }
    if (!isNowPhoto) {
      final source = await showPhotoSourceSheet(context);
      if (source == null || !mounted) return;
      setState(() => _pickingSlot = slot);
      String? picked;
      try {
        picked = await PhotoService.instance.pickAndSaveMemoryPhoto(source: source);
      } catch (_) {
        picked = null;
      }
      if (!mounted) return;
      setState(() {
        _pickingSlot = null;
        if (picked != null) _photoPath = picked;
      });
      if (picked == null) _toast('사진을 불러오지 못했어요');
      return;
    }

    setState(() => _pickingSlot = slot);
    String? path;
    try {
      path = await PhotoService.instance.captureMemoryPhoto();
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    setState(() {
      _pickingSlot = null;
      if (path != null) _afterPhotoPath = path;
    });
    if (path == null) {
      _toast('카메라로 지금 모습을 찍어주세요');
    }
  }

  String get _placeName =>
      _useCustomPlace ? _customPlaceCtrl.text.trim() : (_selectedPlace ?? '');

  void _submit() {
    final place = _placeName;
    final note = _noteCtrl.text.trim();

    if (place.isEmpty) {
      _toast('장소를 선택하거나 입력해주세요');
      return;
    }
    // 짝이 맞아야 비교가 성립하므로 두 장 모두 필수.
    if (_isArchive && (_photoPath == null || _afterPhotoPath == null)) {
      _toast(_photoPath == null
          ? '그때 사진을 올려주세요'
          : '지금 모습을 카메라로 찍어주세요');
      return;
    }
    if (!_isArchive && note.isEmpty && _photoPath == null) {
      _toast('남길 기억이나 사진을 하나는 넣어주세요');
      return;
    }

    Navigator.of(context).pop(
      _ComposeResult(
        placeName: place,
        note: note,
        photoPath: _photoPath,
        afterPhotoPath: _afterPhotoPath,
        beforeYear: _yearCtrl.text.trim(),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
                _isArchive
                    ? (widget.isEditing ? '그때-지금 사진 수정' : '그때-지금 사진 추가하기')
                    : (widget.isEditing ? '방명록 수정' : '새 방명록 남기기'),
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
                  for (final name in widget.placeNames)
                    _SelectChip(
                      label: name,
                      selected: !_useCustomPlace && _selectedPlace == name,
                      onTap: () => setState(() {
                        _useCustomPlace = false;
                        _selectedPlace = name;
                      }),
                    ),
                  _SelectChip(
                    label: '직접 입력',
                    icon: Icons.edit_outlined,
                    selected: _useCustomPlace,
                    onTap: () => setState(() => _useCustomPlace = true),
                  ),
                ],
              ),
              if (_useCustomPlace) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customPlaceCtrl,
                  style: AppTextStyles.input,
                  decoration: const InputDecoration(
                    hintText: '장소 이름을 입력해주세요',
                    hintStyle: AppTextStyles.inputHint,
                  ),
                ),
              ],
              const SizedBox(height: 18),

              _FieldLabel(_isArchive ? '그때 사진 (필수)' : '사진 (선택)'),
              const SizedBox(height: 8),
              _PhotoPickerBox(
                photoPath: _photoPath,
                isLoading: _pickingSlot == _PhotoSlot.before,
                emptyLabel: _isArchive
                    ? '예전에 찍은 사진 가져오기'
                    : '카메라 또는 앨범에서 사진 가져오기',
                onTap: () => _pickPhoto(_PhotoSlot.before),
                // 그때 사진을 빼면 지금 사진도 같이 비워 순서를 유지함.
                onClear: () => setState(() {
                  _photoPath = null;
                  _afterPhotoPath = null;
                }),
              ),

              if (_isArchive) ...[
                const SizedBox(height: 18),
                const _FieldLabel('지금 사진 (필수 · 카메라 촬영)'),
                const SizedBox(height: 8),
                _PhotoPickerBox(
                  photoPath: _afterPhotoPath,
                  isLoading: _pickingSlot == _PhotoSlot.after,
                  enabled: _photoPath != null,
                  emptyLabel: '지금 모습을 카메라로 찍기',
                  lockedLabel: '그때 사진을 먼저 올려주세요',
                  changeLabel: '다시 찍기',
                  changeIcon: Icons.photo_camera_outlined,
                  onTap: () => _pickPhoto(_PhotoSlot.after),
                  onClear: () => setState(() => _afterPhotoPath = null),
                ),
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

              const SizedBox(height: 18),
              _FieldLabel(_isArchive ? '메모 (선택)' : '기억'),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                style: AppTextStyles.input,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _isArchive
                      ? '이 사진에 얽힌 이야기를 적어보세요'
                      : '이 장소에서의 기억을 자유롭게 남겨보세요',
                  hintStyle: AppTextStyles.inputHint,
                ),
              ),
              const SizedBox(height: 18),

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
                    widget.isEditing ? '수정 완료' : '등록하기',
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
  final IconData? icon;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
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
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: selected ? AppColors.accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
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

/// 사진을 고르는 영역. 고른 뒤에는 미리보기 + 변경/빼기.
enum _PhotoSlot { before, after }

class _PhotoPickerBox extends StatelessWidget {
  final String? photoPath;
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
            errorBuilder: (_, __, ___) => Container(
              height: 180,
              alignment: Alignment.center,
              color: AppColors.background,
              child: const Text('사진을 열 수 없어요', style: AppTextStyles.bodySmall),
            ),
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
}

// =============================================================================
// 화면 조각들
// =============================================================================

/// 화면 상단 - 타이틀 + 새 글 작성 버튼.
class _GuestbookTopBar extends StatelessWidget {
  final VoidCallback onAddTap;
  final String addLabel;

  const _GuestbookTopBar({required this.onAddTap, required this.addLabel});

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
                child: const Icon(Icons.add, color: AppColors.cardBackground, size: 20),
              ),
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
            const Icon(Icons.route_outlined, size: AppIconSize.inCardSmall, color: AppColors.text),
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
                '삭제하기',
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
          const Icon(Icons.place_outlined, size: AppIconSize.inCardSmall, color: AppColors.accent),
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
              '예전 사진과 지금 모습 사진을 함께 올리면\n좌우로 밀어 비교할 수 있어요',
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
    final hasPhoto = slot.entry?.hasBeforePhoto ?? false;
    final url = slot.afterImageUrl;
    final ImageProvider? cover = slot.entry?.beforeImage ??
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
