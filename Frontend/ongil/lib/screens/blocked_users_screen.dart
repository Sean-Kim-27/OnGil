import 'package:flutter/material.dart';

import '../models/moderation.dart';
import '../services/moderation_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_text_styles.dart';

/// 내가 차단한 사용자 목록과 차단 해제.
///
/// Play 정책은 차단 기능만 요구하지만, 해제 수단이 없으면 실수로 차단했을 때
/// 되돌릴 방법이 없어서 함께 둔다.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<UserBlock> _blocks = [];
  bool _isLoading = true;
  String? _error;

  /// 해제 요청 중인 사용자 id. 버튼 중복 탭 방지용.
  final Set<int> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final blocks = await ModerationApiService.fetchBlockedUsers();
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _isLoading = false;
      });
    } on ModerationApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '차단 목록을 불러오지 못했어요.';
        _isLoading = false;
      });
    }
  }

  Future<void> _unblock(UserBlock block) async {
    final userId = block.blockedUser.id;
    if (_unblocking.contains(userId)) return;

    setState(() => _unblocking.add(userId));

    try {
      await ModerationApiService.unblockUser(userId);
      if (!mounted) return;
      setState(() {
        _blocks.removeWhere((b) => b.blockedUser.id == userId);
        _unblocking.remove(userId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${block.blockedUser.displayName}님의 차단을 해제했어요.')),
        );
    } on ModerationApiException catch (e) {
      if (!mounted) return;
      setState(() => _unblocking.remove(userId));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _unblocking.remove(userId));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('차단을 해제하지 못했어요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text('차단한 사용자', style: AppTextStyles.screenTitle),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            TextButton(
              onPressed: _load,
              child: Text('다시 시도',
                  style:
                      AppTextStyles.button.copyWith(color: AppColors.accent)),
            ),
          ],
        ),
      );
    }

    if (_blocks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Text(
            '차단한 사용자가 없어요.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      itemCount: _blocks.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (context, i) {
        final block = _blocks[i];
        final user = block.blockedUser;
        final busy = _unblocking.contains(user.id);

        return Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              _Avatar(user: user),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  user.displayName,
                  style: AppTextStyles.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _unblock(block),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      )
                    : Text(
                        '차단 해제',
                        style: AppTextStyles.button
                            .copyWith(color: AppColors.accent),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final ModerationUser user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final url = user.profileImageUrl;
    const size = 38.0;

    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.accentLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        user.initial,
        style: AppTextStyles.cardTitle.copyWith(color: AppColors.accent),
      ),
    );
  }
}
