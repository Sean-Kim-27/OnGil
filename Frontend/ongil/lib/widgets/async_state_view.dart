import 'package:flutter/material.dart';
import '../services/schedule_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 통신 실패를 원인별로 안내하고, 의미 있을 때만 재시도 버튼을 보여주는 공용 위젯.
class ApiErrorView extends StatelessWidget {
  final ScheduleApiException error;
  final VoidCallback? onRetry;

  const ApiErrorView({super.key, required this.error, this.onRetry});

  IconData get _icon {
    switch (error.kind) {
      case ScheduleApiErrorKind.network:
      case ScheduleApiErrorKind.timeout:
        return Icons.wifi_off_rounded;
      case ScheduleApiErrorKind.unauthorized:
        return Icons.lock_outline_rounded;
      case ScheduleApiErrorKind.notFound:
        return Icons.search_off_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, size: 34, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              error.userMessage,
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            if (error.isRetryable && onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 통신은 성공했는데 보여줄 내용이 없는 상태.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;

  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(hint!, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// 리스트 자리에 잠깐 보여주는 뼈대.
class ScheduleCardSkeleton extends StatelessWidget {
  final int count;
  const ScheduleCardSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: AppSpacing.cardGap,
      ),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (_, __) => Container(
        height: 86,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.line),
        ),
      ),
    );
  }
}
