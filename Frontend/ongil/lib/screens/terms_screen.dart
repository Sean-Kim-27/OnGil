import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import '../models/terms_item.dart';

/// 카카오/구글 로그인 전에 보여주는 약관 동의 화면. 필수 항목을 모두 체크해야 CTA가 활성화됨.
/// 동의를 마치면 Navigator.pop(context, true)로 결과만 돌려주고, 실제 로그인은 LoginScreen에서 이어감.
class TermsAgreementScreen extends StatefulWidget {
  /// 상단 안내 문구에 쓰일 provider 이름
  final String providerLabel;

  const TermsAgreementScreen({super.key, required this.providerLabel});

  @override
  State<TermsAgreementScreen> createState() => _TermsAgreementScreenState();
}

class _TermsAgreementScreenState extends State<TermsAgreementScreen> {
  List<bool> _checked = List.filled(AppTerms.items.length, false);

  bool get _allChecked => _checked.every((c) => c);

  bool get _requiredChecked {
    for (int i = 0; i < AppTerms.items.length; i++) {
      if (AppTerms.items[i].isRequired && !_checked[i]) return false;
    }
    return true;
  }

  void _toggleAll(bool? value) {
    setState(() => _checked = List.filled(AppTerms.items.length, value ?? false));
  }

  void _toggleOne(int index, bool? value) {
    setState(() => _checked[index] = value ?? false);
  }

  void _showDetail(TermsItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.cardLarge)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.title, style: AppTextStyles.screenTitle),
              const SizedBox(height: 12),
              Text(item.content, style: AppTextStyles.body),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _confirm() {
    if (!_requiredChecked) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppBackTopBar(title: '약관 동의'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      '${widget.providerLabel}(으)로 계속하려면\n약관에 동의해주세요',
                      style: AppTextStyles.heroCopy,
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    _AllAgreeRow(checked: _allChecked, onChanged: _toggleAll),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.line, height: 1),
                    const SizedBox(height: 4),
                    for (int i = 0; i < AppTerms.items.length; i++)
                      _TermRow(
                        item: AppTerms.items[i],
                        checked: _checked[i],
                        onChanged: (v) => _toggleOne(i, v),
                        onDetailTap: () => _showDetail(AppTerms.items[i]),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.bottomBarHorizontal,
                AppSpacing.bottomBarTop,
                AppSpacing.bottomBarHorizontal,
                AppSpacing.bottomBarBottom,
              ),
              child: PrimaryButton(
                label: '동의하고 계속하기',
                onPressed: _requiredChecked ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllAgreeRow extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;
  const _AllAgreeRow({required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _CheckCircle(checked: checked, big: true),
            const SizedBox(width: 10),
            Text(
              '모두 동의합니다',
              style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  final TermsItem item;
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onDetailTap;

  const _TermRow({
    required this.item,
    required this.checked,
    required this.onChanged,
    required this.onDetailTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            _CheckCircle(checked: checked),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: item.isRequired ? '[필수] ' : '[선택] ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: item.isRequired ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: item.title, style: AppTextStyles.body),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: onDetailTap,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final bool checked;
  final bool big;
  const _CheckCircle({required this.checked, this.big = false});

  @override
  Widget build(BuildContext context) {
    final size = big ? 24.0 : 20.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppColors.accent : Colors.transparent,
        border: Border.all(color: checked ? AppColors.accent : AppColors.line, width: 1.3),
      ),
      child: checked
          ? Icon(Icons.check, size: big ? 15 : 13, color: AppColors.cardBackground)
          : null,
    );
  }
}
