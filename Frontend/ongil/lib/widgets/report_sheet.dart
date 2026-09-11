import 'package:flutter/material.dart';

import '../models/moderation.dart';
import '../services/moderation_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 신고 사유를 고르고 상세 설명을 적는 시트.
///
/// 신고가 접수되면 true를 돌려준다. 취소하면 null.
///
/// 스크롤이 되어야 사유가 잘리지 않으므로 `DraggableScrollableSheet`가 아니라
/// 키보드 높이를 따라가는 `Padding` + `SingleChildScrollView` 조합을 쓴다.
class ReportSheet extends StatefulWidget {
  /// 신고 대상 방명록 id.
  final int guestbookId;

  /// 화면에 보여줄 작성자 이름.
  final String authorName;

  const ReportSheet({
    super.key,
    required this.guestbookId,
    required this.authorName,
  });

  /// 시트를 띄우고 결과를 받는다.
  static Future<bool?> show(
    BuildContext context, {
    required int guestbookId,
    required String authorName,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReportSheet(
        guestbookId: guestbookId,
        authorName: authorName,
      ),
    );
  }

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _detailController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ModerationApiService.reportGuestbook(
        guestbookId: widget.guestbookId,
        reason: reason,
        details: _detailController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ModerationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // 이미 신고한 글이면 사용자 입장에선 목적을 달성한 것이라 성공으로 닫는다.
        if (e.kind == ModerationErrorKind.conflict) {
          Navigator.of(context).pop(true);
          return;
        }
        _error = e.userMessage;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '신고를 접수하지 못했어요. 잠시 후 다시 시도해주세요.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.cardHero),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              10,
              AppSpacing.screenHorizontal,
              AppSpacing.bottomBarBottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                Text('신고하기', style: AppTextStyles.screenTitle),
                const SizedBox(height: 6),
                Text(
                  '${widget.authorName}님의 방명록을 신고합니다.\n신고 내용은 운영자가 확인합니다.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                Text('신고 사유', style: AppTextStyles.cardTitle),
                const SizedBox(height: AppSpacing.cardGap),
                for (final reason in ReportReason.values) ...[
                  _ReasonTile(
                    reason: reason,
                    selected: _reason == reason,
                    onTap: _submitting
                        ? null
                        : () => setState(() => _reason = reason),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: AppSpacing.cardGap),
                Text('상세 설명 (선택)', style: AppTextStyles.cardTitle),
                const SizedBox(height: 8),
                TextField(
                  controller: _detailController,
                  enabled: !_submitting,
                  maxLines: 3,
                  maxLength: ModerationApiService.maxDetailLength,
                  style: AppTextStyles.input,
                  decoration: InputDecoration(
                    hintText: '어떤 점이 문제인지 알려주시면 확인에 도움이 됩니다.',
                    hintStyle: AppTextStyles.inputHint,
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    contentPadding:
                        const EdgeInsets.all(AppSpacing.cardPadding),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.accent),
                  ),
                  const SizedBox(height: AppSpacing.cardGap),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        (_reason == null || _submitting) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor: AppColors.line,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            '신고 접수',
                            style: AppTextStyles.button
                                .copyWith(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final ReportReason reason;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.cardPadding,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentLight : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                reason.label,
                style: AppTextStyles.body.copyWith(
                  color: selected ? AppColors.accent : AppColors.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
