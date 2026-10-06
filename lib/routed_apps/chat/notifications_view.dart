import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 系统通知列表。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final NotificationsController controller;

  /// 哪些公告被展开正文。键是公告 id，列表刷新后折叠状态重置。
  final Set<int> _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    controller = Get.put(NotificationsController());
  }

  @override
  void dispose() {
    Get.delete<NotificationsController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          // 注意：AppBar actions 处于无界宽度测量环境，
          // 不能用主题里 minimumSize=Size.fromHeight(48) 的 TextButton（无限最小宽会炸布局），
          // 必须用有限尺寸的 ChatSmallButton。
          Padding(
            padding: const EdgeInsets.only(right: AppDesign.spaceM),
            child: ChatSmallButton(
              label: '全部已读',
              variant: ChatButtonVariant.tonal,
              onPressed: controller.notifications.isEmpty
                  ? null
                  : controller.markAllRead,
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.notifications.isEmpty) {
          return const AppLoading();
        }
        if (controller.errorMessage.value.isNotEmpty &&
            controller.notifications.isEmpty) {
          return AppEmptyState(
            icon: Icons.wifi_off_outlined,
            message: controller.errorMessage.value,
            actionLabel: '重试',
            onAction: controller.load,
          );
        }
        if (controller.notifications.isEmpty) {
          return const AppEmptyState(
            icon: Icons.notifications_none,
            message: '暂无通知',
            verticalPadding: AppDesign.spaceL,
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
                    children: [
                      // 新通知实时到达时直接刷新列表。
                      for (final n in controller.notifications)
                        _notificationCard(context, n),
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

  Widget _notificationCard(BuildContext context, AppNotification n) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = context.statusStyleOf(_statusOf(n.type));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        accentColor: n.read ? null : scheme.primary,
        padding: const EdgeInsets.all(AppDesign.spaceS),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: style.background,
                shape: BoxShape.circle,
              ),
              child: Icon(_icon(n.type), size: 19, color: style.foreground),
            ),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: n.read ? FontWeight.w500 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesign.spaceXS),
                      Text(
                        ChatTimeFmt.shortTime(n.createdAt),
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (n.content.isNotEmpty) ...[
                    const SizedBox(height: AppDesign.spaceXXS),
                    _expandableBody(context, n),
                  ],
                  const SizedBox(height: AppDesign.spaceXS),
                  AppStatusChip(
                    label: _typeLabel(n.type),
                    status: _statusOf(n.type),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'friend_request':
        return '好友申请';
      case 'friend_accepted':
        return '好友通过';
      case 'system_announce':
        return '系统公告';
      default:
        return '通知';
    }
  }

  static AppStatus _statusOf(String type) {
    switch (type) {
      case 'friend_request':
        return AppStatus.info;
      case 'friend_accepted':
        return AppStatus.success;
      case 'system_announce':
        return AppStatus.warning;
      default:
        return AppStatus.neutral;
    }
  }

  static IconData _icon(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add_alt_outlined;
      case 'friend_accepted':
        return Icons.how_to_reg_outlined;
      case 'system_announce':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  /// 公告正文：默认折叠到 6 行，纯文本超过一定长度时显示「展开/收起」。
  ///
  /// 服务端允许 500 字内容，但通知卡片只是列表条目，不能让一条公告顶掉整个列表。
  Widget _expandableBody(BuildContext context, AppNotification n) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final plain = ChatMarkdown.strip(n.content);
    final expanded = _expanded.contains(n.id);
    const threshold = 120;
    final canToggle = plain.length > threshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plain,
          maxLines: expanded ? null : 6,
          overflow:
              expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (canToggle) ...[
          const SizedBox(height: AppDesign.spaceXXXS),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (expanded) {
                  _expanded.remove(n.id);
                } else {
                  _expanded.add(n.id);
                }
              }),
              child: Text(
                expanded ? '收起' : '展开',
                style: text.labelSmall?.copyWith(color: scheme.primary),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
