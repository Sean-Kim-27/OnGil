import 'package:flutter/material.dart';

import '../models/guestbook_entry.dart';
import '../services/guestbook_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

class GuestbookScreen extends StatefulWidget {
  final GuestbookRepository? repository;

  const GuestbookScreen({super.key, this.repository});

  @override
  State<GuestbookScreen> createState() => _GuestbookScreenState();
}

class _GuestbookScreenState extends State<GuestbookScreen> {
  late final GuestbookRepository _repository;
  List<GuestbookEntry> _entries = const [];
  final Set<int> _submittingEntryIds = <int>{};
  int? _currentUserId;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? GuestbookService.instance;
    _loadFeed();
  }

  Future<void> _loadFeed() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final userIdFuture = _repository.fetchCurrentUserId();
      final feedFuture = _repository.fetchFeed();
      final userId = await userIdFuture;
      final feed = await feedFuture;
      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _entries = feed.items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _report(GuestbookEntry entry) async {
    final detailsController = TextEditingController();
    var selectedReason = GuestbookReportReason.spam;
    final draft = await showDialog<_ReportDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('방명록 신고'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('신고 사유를 선택해 주세요.'),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<GuestbookReportReason>(
                      initialValue: selectedReason,
                      decoration: const InputDecoration(
                        labelText: '신고 사유',
                        border: OutlineInputBorder(),
                      ),
                      items: GuestbookReportReason.values
                          .map(
                            (reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(reason.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (reason) {
                        if (reason != null) {
                          setDialogState(() => selectedReason = reason);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: detailsController,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '상세 내용 (선택)',
                        hintText: '관리자가 확인할 내용을 적어주세요.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(
                    _ReportDraft(selectedReason, detailsController.text),
                  ),
                  child: const Text('신고하기'),
                ),
              ],
            );
          },
        );
      },
    );
    detailsController.dispose();
    if (draft == null || !mounted) return;

    setState(() => _submittingEntryIds.add(entry.id));
    try {
      await _repository.reportGuestbook(
        guestbookId: entry.id,
        reason: draft.reason,
        details: draft.details,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('신고가 접수됐어요. 관리자가 확인할게요.')),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _submittingEntryIds.remove(entry.id));
      }
    }
  }

  Future<void> _block(GuestbookEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${entry.author.nickname ?? '이 사용자'}님을 차단할까요?'),
        content: const Text(
          '차단하면 앞으로 이 사용자의 방명록이 내 피드와 상세 화면에 표시되지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('차단하기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submittingEntryIds.add(entry.id));
    try {
      await _repository.blockUser(entry.author.id);
      if (!mounted) return;
      setState(() {
        _entries = _entries
            .where((item) => item.author.id != entry.author.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('사용자를 차단했어요.'),
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () => _undoBlock(entry.author.id),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _submittingEntryIds.remove(entry.id));
      }
    }
  }

  Future<void> _undoBlock(int userId) async {
    try {
      await _repository.unblockUser(userId);
      await _loadFeed();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              18,
              AppSpacing.screenHorizontal,
              12,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('방명록', style: AppTextStyles.screenTitle),
                      SizedBox(height: 4),
                      Text(
                        '함께 걸었던 장소의 이야기를 만나보세요.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '새로고침',
                  onPressed: _isLoading ? null : _loadFeed,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _GuestbookMessage(
        icon: Icons.cloud_off_outlined,
        message: _errorMessage!,
        actionLabel: '다시 시도',
        onAction: _loadFeed,
      );
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFeed,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            _GuestbookMessage(
              icon: Icons.menu_book_outlined,
              message: '아직 표시할 방명록이 없어요.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          4,
          AppSpacing.screenHorizontal,
          100,
        ),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _GuestbookCard(
            entry: entry,
            isSubmitting: _submittingEntryIds.contains(entry.id),
            showModerationActions: entry.author.id != _currentUserId,
            onReport: () => _report(entry),
            onBlock: () => _block(entry),
          );
        },
      ),
    );
  }
}

class _GuestbookCard extends StatelessWidget {
  final GuestbookEntry entry;
  final bool isSubmitting;
  final bool showModerationActions;
  final VoidCallback onReport;
  final VoidCallback onBlock;

  const _GuestbookCard({
    required this.entry,
    required this.isSubmitting,
    required this.showModerationActions,
    required this.onReport,
    required this.onBlock,
  });

  @override
  Widget build(BuildContext context) {
    final rawNickname = entry.author.nickname?.trim() ?? '';
    final nickname = rawNickname.isEmpty ? '온길 사용자' : rawNickname;
    final profileUrl = entry.author.profileImageUrl;
    final photo = entry.photos.isEmpty ? null : entry.photos.first;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPaddingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.brandLight,
                  backgroundImage: profileUrl == null || profileUrl.isEmpty
                      ? null
                      : NetworkImage(profileUrl),
                  child: profileUrl == null || profileUrl.isEmpty
                      ? Text(
                          nickname.characters.first,
                          style: AppTextStyles.cardTitle,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nickname, style: AppTextStyles.cardTitle),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.place.name} · ${_formatDate(entry.createdAt)}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                if (isSubmitting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (showModerationActions)
                  PopupMenuButton<_GuestbookAction>(
                    tooltip: '신고 및 차단 메뉴',
                    onSelected: (action) {
                      switch (action) {
                        case _GuestbookAction.report:
                          onReport();
                        case _GuestbookAction.block:
                          onBlock();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _GuestbookAction.report,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_outlined),
                          title: Text('신고하기'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _GuestbookAction.block,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.block_outlined),
                          title: Text('사용자 차단'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (entry.content != null && entry.content!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(entry.content!, style: AppTextStyles.body),
            ],
            if (photo != null) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.thumbnail),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: Image.network(
                    GuestbookService.resolveMediaUrl(
                      photo.mosaicImageUrl ?? photo.imageUrl,
                    ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.background,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (entry.photos.length > 1) ...[
                const SizedBox(height: 6),
                Text(
                  '사진 ${entry.photos.length}장',
                  style: AppTextStyles.caption,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _GuestbookMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GuestbookMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

enum _GuestbookAction { report, block }

class _ReportDraft {
  final GuestbookReportReason reason;
  final String details;

  const _ReportDraft(this.reason, this.details);
}
