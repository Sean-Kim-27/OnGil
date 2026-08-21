import 'package:flutter/material.dart';
import '../controllers/app_shell_controller.dart';
import '../controllers/schedule_detail_controller.dart';
import '../models/schedule.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/async_state_view.dart';
import '../widgets/category_icon_box.dart';

/// 여정 상세 - 방문 순서대로 정리된 타임라인.
class ScheduleDetailScreen extends StatefulWidget {
  final int scheduleId;

  /// 이미 상세를 들고 있으면 넘겨서 재조회를 생략함.
  final ScheduleDetail? initialDetail;

  /// 생성 직후 진입이면 뒤로가기가 홈 셸로 빠져나감.
  final bool justCreated;

  const ScheduleDetailScreen({
    super.key,
    required this.scheduleId,
    this.initialDetail,
    this.justCreated = false,
  });

  @override
  State<ScheduleDetailScreen> createState() => _ScheduleDetailScreenState();
}

class _ScheduleDetailScreenState extends State<ScheduleDetailScreen> {
  final ScheduleDetailController _controller = ScheduleDetailController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    if (widget.initialDetail != null) {
      _controller.seed(widget.initialDetail!);
    } else {
      _controller.load(widget.scheduleId);
    }
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

  @override
  Widget build(BuildContext context) {
    final detail = _controller.detail;

    return PopScope(
      // 생성 직후엔 시스템 뒤로가기도 홈 셸로 보냄.
      canPop: !widget.justCreated,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToScheduleList();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              AppBackTopBar(
                title: detail?.title ?? '여정',
                onBack: widget.justCreated
                    ? _goToScheduleList
                    : () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: _buildBody(detail)),
              if (detail != null && detail.places.isNotEmpty)
                _DetailActionBar(
                  hasRoute: detail.routePlaces.isNotEmpty,
                  onShowOnMap: () => _openOnMap(detail),
                  onGoToList: _goToScheduleList,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 지도 탭으로 이동하며 이 여정의 경로를 그려달라고 요청.
  void _openOnMap(ScheduleDetail detail) {
    if (detail.routePlaces.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 여정에는 지도에 표시할 좌표가 없어요')),
      );
      return;
    }
    AppShellController.instance.openHomeTab(
      context,
      tabIndex: 0,
      focusScheduleId: detail.id,
    );
  }

  void _goToScheduleList() {
    AppShellController.instance.openHomeTab(context, tabIndex: 1);
  }

  Widget _buildBody(ScheduleDetail? detail) {
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_controller.hasError) {
      return ApiErrorView(
        error: _controller.error!,
        onRetry: () => _controller.load(widget.scheduleId),
      );
    }

    if (detail == null) {
      return const EmptyStateView(
        icon: Icons.map_outlined,
        message: '여정 정보를 불러오지 못했어요',
      );
    }

    if (detail.places.isEmpty) {
      // 통신은 됐는데 장소가 비어 있는 경우.
      return Column(
        children: [
          _DetailHeader(detail: detail),
          const Expanded(
            child: EmptyStateView(
              icon: Icons.place_outlined,
              message: '이 여정에 담긴 장소가 없어요',
              hint: '장소를 추가하면 여기에 순서대로 표시돼요',
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.cardBackground,
      onRefresh: () => _controller.load(widget.scheduleId),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap * 2),
        children: [
          _DetailHeader(detail: detail),
          for (final day in detail.days) ...[
            // 하루짜리 여정이면 '1일차' 머리말을 생략.
            if (detail.days.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.cardGap,
                  AppSpacing.screenHorizontal,
                  6,
                ),
                child: Text('${day.dayNo}일차', style: AppTextStyles.cardTitle),
              ),
            for (int i = 0; i < day.places.length; i++)
              _TimelineTile(
                place: day.places[i],
                isLast: i == day.places.length - 1,
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final ScheduleDetail detail;
  const _DetailHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final subtitle = detail.subtitle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        6,
        AppSpacing.screenHorizontal,
        AppSpacing.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detail.title, style: AppTextStyles.heroGreeting),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: 11),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (detail.tripTypeLabel.isNotEmpty) _MetaChip(label: detail.tripTypeLabel),
              if (detail.mobilityLabel.isNotEmpty)
                _MetaChip(
                  label: detail.mobilityLabel,
                  icon: detail.isWalking
                      ? Icons.directions_walk_rounded
                      : Icons.directions_car_filled_outlined,
                ),
              _MetaChip(label: '${detail.places.length}곳', icon: Icons.place_outlined),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _MetaChip({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppIconSize.inCardSmall, color: AppColors.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

/// 타임라인 한 칸.
class _TimelineTile extends StatelessWidget {
  final SchedulePlace place;
  final bool isLast;

  const _TimelineTile({required this.place, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final category = categoryLabel(place.category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                CategoryIconBox(category: place.category, order: place.visitOrder),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.line,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.cardPadding),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              place.title,
                              style: AppTextStyles.cardTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 서버가 시간을 안 주면 자리를 아예 만들지 않음.
                          if (place.timeSlot != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              place.timeSlot!,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (category.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(category, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// 여정 상세 하단 액션(지도로 보기 / 목록으로).
class _DetailActionBar extends StatelessWidget {
  final bool hasRoute;
  final VoidCallback onShowOnMap;
  final VoidCallback onGoToList;

  const _DetailActionBar({
    required this.hasRoute,
    required this.onShowOnMap,
    required this.onGoToList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        12,
        AppSpacing.screenHorizontal,
        16,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: hasRoute ? onShowOnMap : null,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('지도에서 경로 보기'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: onGoToList,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: const BorderSide(color: AppColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
                child: const Text('스케줄 목록'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
