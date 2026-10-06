import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 好友申请处理页：收到的申请（可同意/拒绝）+ 我发出的申请。
class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  late final FriendRequestsController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(FriendRequestsController());
  }

  @override
  void dispose() {
    Get.delete<FriendRequestsController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: Obx(() {
        final empty =
            controller.inbox.isEmpty && controller.outbox.isEmpty;
        if (controller.isLoading.value && empty) {
          return const AppLoading();
        }
        if (controller.errorMessage.value.isNotEmpty && empty) {
          return AppEmptyState(
            icon: Icons.wifi_off_outlined,
            message: controller.errorMessage.value,
            actionLabel: '重试',
            onAction: controller.load,
          );
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            // 内容不足一屏时也必须可拖动，否则下拉刷新失效。
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDesign.spaceM),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppDesign.maxContentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(
                        context,
                        title: '收到的申请',
                        icon: Icons.downloading,
                        count: controller.inbox.length,
                      ),
                      const SizedBox(height: AppDesign.spaceXS),
                      if (controller.inbox.isEmpty)
                        const AppEmptyState(
                          icon: Icons.inbox_outlined,
                          message: '暂无收到的申请',
                          verticalPadding: AppDesign.spaceL,
                        )
                      else
                        for (final r in controller.inbox)
                          _inboxCard(context, r),
                      const SizedBox(height: AppDesign.spaceL),
                      _sectionHeader(
                        context,
                        title: '我发出的申请',
                        icon: Icons.outbox,
                        count: controller.outbox.length,
                      ),
                      const SizedBox(height: AppDesign.spaceXS),
                      if (controller.outbox.isEmpty)
                        const AppEmptyState(
                          icon: Icons.send_outlined,
                          message: '暂无发出的申请',
                          verticalPadding: AppDesign.spaceL,
                        )
                      else
                        for (final r in controller.outbox)
                          _outboxCard(context, r),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
  }) {
    return AppSectionHeader(
      title: title,
      icon: icon,
      trailing: count == 0
          ? null
          : Text(
              '共 $count 条',
              style: Theme.of(context).textTheme.labelSmall,
            ),
    );
  }

  Widget _inboxCard(BuildContext context, FriendRequest r) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = r.fromNickname.isEmpty ? r.fromUsername : r.fromNickname;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ChatAvatar(
                  userId: r.fromUserId,
                  name: name,
                  hasAvatar: r.fromHasAvatar,
                  avatarUpdatedAt: r.fromAvatarUpdatedAt,
                  onTap: () =>
                      Get.to(() => UserProfilePage(userId: r.fromUserId)),
                ),
                const SizedBox(width: AppDesign.spaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppDesign.spaceXXXS),
                      ChatSubLine('用户名：${r.fromUsername}'),
                    ],
                  ),
                ),
                const SizedBox(width: AppDesign.spaceXS),
                Text(
                  ChatTimeFmt.shortTime(r.createdAt),
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (r.message.trim().isNotEmpty) ...[
              const SizedBox(height: AppDesign.spaceXS),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.spaceS,
                  vertical: AppDesign.spaceXS,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppDesign.radiusS),
                ),
                child: Text(
                  r.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            const SizedBox(height: AppDesign.spaceS),
            if (r.isPending)
              Row(
                children: [
                  Expanded(
                    child: ChatSmallButton(
                      label: '拒绝',
                      variant: ChatButtonVariant.outlined,
                      onPressed: () => controller.respond(r, false),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spaceS),
                  Expanded(
                    child: ChatSmallButton(
                      label: '同意',
                      icon: Icons.check,
                      onPressed: () => controller.respond(r, true),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: _statusChip(r.status),
              ),
          ],
        ),
      ),
    );
  }

  Widget _outboxCard(BuildContext context, FriendRequest r) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = r.toNickname.isEmpty ? r.toUsername : r.toNickname;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        child: Row(
          children: [
            ChatAvatar(
              userId: r.toUserId,
              name: name,
              hasAvatar: r.toHasAvatar,
              avatarUpdatedAt: r.toAvatarUpdatedAt,
              onTap: () => Get.to(() => UserProfilePage(userId: r.toUserId)),
            ),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppDesign.spaceXXXS),
                  ChatSubLine('用户名：${r.toUsername}'),
                ],
              ),
            ),
            const SizedBox(width: AppDesign.spaceXS),
            if (r.isPending)
              const AppStatusChip(label: '待对方处理', status: AppStatus.warning)
            else
              _statusChip(r.status),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(int status) {
    return switch (status) {
      1 => const AppStatusChip(
          label: '已同意',
          status: AppStatus.success,
          icon: Icons.check_circle_outline,
        ),
      2 => const AppStatusChip(
          label: '已拒绝',
          status: AppStatus.danger,
          icon: Icons.remove_circle_outline,
        ),
      _ => const AppStatusChip(label: '已处理', status: AppStatus.neutral),
    };
  }
}
