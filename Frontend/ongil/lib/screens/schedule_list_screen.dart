import 'package:flutter/material.dart';
import '../controllers/schedule_list_controller.dart';
import '../models/schedule.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/async_state_view.dart';
import '../widgets/category_icon_box.dart';
import 'schedule_detail_screen.dart';

/// 내 여정 목록. 홈의 '스케줄' 탭 본문이자 '/schedule_list' 라우트.
class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key});

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  final ScheduleListController _controller = ScheduleListController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _controller.fetchSchedules();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  /// 상세에서 돌아오면 목록을 조용히 갱신.
  Future<void> _openDetail(ScheduleSummary schedule) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleDetailScreen(scheduleId: schedule.id),
      ),
    );
    if (mounted) _controller.fetchSchedules(silent: true);
  }

  Future<void> _confirmDelete(ScheduleSummary schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        title: const Text('여정을 삭제할까요?', style: AppTextStyles.screenTitle),
        content: Text(
          "'${schedule.title}'을(를) 삭제하면 되돌릴 수 없어요.",
          style: AppTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('취소', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '삭제',
              style: AppTextStyles.body.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await _controller.deleteSchedule(schedule.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '여정을 삭제했어요' : (_controller.error?.userMessage ?? '삭제에 실패했어요')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _ListHeader(),
            Expanded(child: _buildBody()),
            _CreateButton(
              onPressed: () async {
                await Navigator.pushNamed(context, '/place_select');
                if (mounted) _controller.fetchSchedules(silent: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading) {
      return const ScheduleCardSkeleton();
    }

    if (_controller.hasError) {
      return ApiErrorView(
        error: _controller.error!,
        onRetry: () => _controller.fetchSchedules(),
      );
    }

    if (_controller.isEmpty) {
      return const EmptyStateView(
        icon: Icons.alt_route_outlined,
        message: '아직 만든 여정이 없어요',
        hint: '아래 버튼으로 첫 여정을 만들어보세요',
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () => _controller.fetchSchedules(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenHorizontal,
          AppSpacing.cardGap,
          AppSpacing.screenHorizontal,
          AppSpacing.sectionGap,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _controller.schedules.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
        itemBuilder: (context, index) {
          final schedule = _controller.schedules[index];
          return _ScheduleCard(
            schedule: schedule,
            onTap: () => _openDetail(schedule),
            onDelete: () => _confirmDelete(schedule),
          );
        },
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.topBarTop,
        AppSpacing.screenHorizontal,
        AppSpacing.topBarBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('스케줄', style: AppTextStyles.heroGreeting),
          const SizedBox(height: 4),
          const Text('추억 좌표를 기준으로 완성된 여정들', style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

/// 여정 한 건. 카드 전체가 탭 가능하고, 오른쪽 메뉴로 삭제할 수 있음.
class _ScheduleCard extends StatelessWidget {
  final ScheduleSummary schedule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScheduleCard({
    required this.schedule,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // 값이 있는 조각만 이어붙임.
    final meta = <String>[
      if (schedule.dateLabel.isNotEmpty) schedule.dateLabel,
      if (schedule.mobilityLabel.isNotEmpty) schedule.mobilityLabel,
      if (schedule.placeCount > 0) '${schedule.placeCount}곳',
    ].join(' · ');

    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPaddingLarge),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const CategoryIconBox(category: 'course'),
              const SizedBox(width: AppSpacing.cardPadding),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.title,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (schedule.tripTypeLabel.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      _TripTypeChip(label: schedule.tripTypeLabel),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                tooltip: '여정 삭제',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripTypeChip extends StatelessWidget {
  final String label;
  const _TripTypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 화면당 강한 CTA는 이거 하나. 나머지는 아웃라인/고스트.
class _CreateButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CreateButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.bottomBarHorizontal,
        AppSpacing.bottomBarTop,
        AppSpacing.bottomBarHorizontal,
        AppSpacing.bottomBarBottom,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 6),
              Text('새로운 스케줄 만들기'),
            ],
          ),
        ),
      ),
    );
  }
}
