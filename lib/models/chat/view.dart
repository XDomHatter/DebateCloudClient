import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_detail_view.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/contacts_view.dart';
import 'package:debate_cloud/routed_apps/chat/friend_requests_view.dart';
import 'package:debate_cloud/routed_apps/chat/group_chat_view.dart';
import 'package:debate_cloud/routed_apps/chat/notifications_view.dart';
import 'package:debate_cloud/routed_apps/login/view.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_server_action.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 消息 tab 首页：会话列表 + 好友/申请/通知入口。
class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key});

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  late final ChatHomeController controller;

  /// 富文本渲染开关。
  ///
  /// Markdown / LaTeX 是对历史消息的**重新解释**：老消息里当价格、当强调用的
  /// `$`、`*` 会被渲染成公式或格式，所以必须留一个全局关闭的退路。
  Widget _richTextMenu() {
    return AppTooltip(
      message: '聊天显示设置',
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          if (value != 'rich') return;
          ChatSettings.setRichTextEnabled(!ChatSettings.richTextEnabled.value);
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem<String>(
            value: 'rich',
            checked: ChatSettings.richTextEnabled.value,
            child: const Text('渲染 Markdown 与公式'),
          ),
        ],
      ),
    );
  }

  /// 顶部区块在宽屏上不应被拉成一条，限制在会话区左上角。
  ///
  /// 宽度必须**同时**施加给入口行与空态：`AppEmptyState` 是「自身收缩包裹 + 内部居中」，
  /// 直接放进左对齐的 Column 里会贴左，视觉中心与上方撑满的入口行错开（宽屏约 144px）。
  static const double _topSectionMaxWidth = 560;

  @override
  void initState() {
    super.initState();
    controller = Get.put(ChatHomeController());
  }

  @override
  void dispose() {
    _selected.dispose();
    Get.delete<ChatHomeController>();
    super.dispose();
  }

  /// 桌面端双栏：左侧会话列表常驻，右侧直接打开会话。
  ///
  /// 窄屏下点会话是整页 push，回来要重新找位置；宽屏有足够横向空间，
  /// 做成 master-detail 才能保住上下文。两条路径复用同一套列表与详情组件，
  /// 只在点击行为上分叉（见 [_openEntry]）。
  static const double _listPaneWidth = 340;

  /// 桌面端当前打开的会话；null 表示右侧是占位空态。
  final _selected = ValueNotifier<Object?>(null);

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthService>();
    if (context.isExpanded) return _buildWorkspace(context, auth);
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [_richTextMenu(), const AppServerAction()],
      ),
      body: Obx(() => _buildBody(context, auth)),
    );
  }

  Widget _buildWorkspace(BuildContext context, AuthService auth) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _listPaneWidth,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('消息'),
                actions: [_richTextMenu(), const AppServerAction()],
              ),
              body: Obx(() => _buildBody(context, auth)),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildDetailPane()),
        ],
      ),
    );
  }

  /// 右侧详情栏：按选中的条目挂载对应的会话页。
  ///
  /// 用 `ValueKey` 强制切换会话时重建——否则 Flutter 会复用上一个
  /// StatefulWidget，`ChatDetailController` 不会重新拉取对方的消息。
  Widget _buildDetailPane() {
    return ValueListenableBuilder<Object?>(
      valueListenable: _selected,
      builder: (context, entry, _) {
        if (entry == null) {
          return const AppEmptyState(
            icon: Icons.chat_bubble_outline,
            title: '未选择会话',
            message: '从左侧选择一个好友或群聊，聊天内容会显示在这里',
            verticalPadding: AppDesign.spaceXXL,
          );
        }
        return switch (entry) {
          Friend f => ChatDetailPage(
            key: ValueKey('chat-friend-${f.userId}'),
            friend: f,
          ),
          ChatGroup g => GroupChatPage(
            key: ValueKey('chat-group-${g.groupId}'),
            group: g,
          ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  /// 打开一个会话：宽屏就地切换右侧栏，窄屏整页 push。
  Future<void> _openEntry(BuildContext context, Object entry) async {
    if (context.isExpanded) {
      _selected.value = entry;
      // 与窄屏返回时一样，顺带刷新一次，把未读计数清掉。
      await controller.load();
      return;
    }
    await Get.to(
      () => switch (entry) {
        Friend f => ChatDetailPage(friend: f),
        ChatGroup g => GroupChatPage(group: g),
        _ => const SizedBox.shrink(),
      },
    );
    await controller.load();
  }

  Widget _buildBody(BuildContext context, AuthService auth) {
    if (!auth.isLoggedIn) {
      return _loginPrompt(context);
    }
    // 只有首屏才用骨架屏，刷新时保持列表可见。
    if (controller.isLoading.value && controller.conversations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppDesign.spaceM),
        child: AppSkeletonList(itemCount: 6),
      );
    }
    final entries = ChatHomeController.mergeEntries(
      controller.conversations,
      controller.groups,
    );
    final hasNotice = controller.errorMessage.value.isNotEmpty ||
        (controller.conversations.isEmpty && controller.groups.isEmpty);
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.builder(
        // 内容不足一屏时也必须可拖动，否则下拉刷新失效。
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppDesign.spaceM),
        // builder 才能虚拟化：会话一多，整列表一帧内全量布局正是移动
        // 端滚动卡顿的来源。第 0 项是入口行（含错误/空态），其余是 tile。
        itemCount: hasNotice ? 1 : entries.length + 1,
        itemBuilder: (context, index) {
          Widget content;
          if (index == 0) {
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topSection(_entryRow(context)),
                const SizedBox(height: AppDesign.spaceL),
                if (hasNotice)
                  controller.errorMessage.value.isNotEmpty
                      ? _topSection(
                          AppEmptyState(
                            icon: Icons.wifi_off_outlined,
                            title: '加载失败',
                            message: controller.errorMessage.value,
                            hint: '会话列表需要服务器连接',
                            actionLabel: '重试',
                            onAction: controller.load,
                          ),
                        )
                      : _topSection(
                          const AppEmptyState(
                            icon: Icons.forum_outlined,
                            title: '暂无会话',
                            message: '去添加好友或发起群聊，聊起来后这里会按时间排列',
                            verticalPadding: AppDesign.spaceM,
                          ),
                        ),
              ],
            );
          } else {
            final e = entries[index - 1];
            content = switch (e) {
              Friend f => _conversationTile(context, f),
              ChatGroup g => _groupTile(context, g),
              _ => const SizedBox.shrink(),
            };
          }
          // 原整列限宽容器逐项等价拆分；key 让元素随数据移动复用，
          // 重排时不再全量重拉头像。
          return Center(
            key: index == 0
                ? null
                : ValueKey(switch (entries[index - 1]) {
                    Friend f => 'conv-u-${f.userId}',
                    ChatGroup g => 'conv-g-${g.groupId}',
                    _ => 'conv-?$index',
                  }),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppDesign.maxContentWidth),
              child: content,
            ),
          );
        },
      ),
    );
  }

  /// 顶部区块（入口行 / 空态 / 错误态）的统一宽度容器。
  ///
  /// 先限宽再撑满并居中：`AppEmptyState` 只按内容收缩，不套 `SizedBox(width: infinity)`
  /// 拿不到紧约束，`Center` 也就无从把它摆到入口行的中线上。
  Widget _topSection(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _topSectionMaxWidth),
      child: SizedBox(width: double.infinity, child: Center(child: child)),
    );
  }

  Widget _loginPrompt(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppEmptyState(
            icon: Icons.lock_outline,
            message: '登录后即可使用聊天',
            verticalPadding: AppDesign.spaceM,
          ),
          FilledButton(onPressed: () => Get.to(() => LoginView()), child: const Text('去登录')),
        ],
      ),
    );
  }

  Widget _entryRow(BuildContext context) {
    final socket = Get.find<ChatSocket>();
    return Row(
      children: [
        Expanded(
          child: _entryCard(
            context,
            icon: Icons.people_outline,
            label: '好友',
            onTap: () async {
              await Get.to(() => ContactsPage());
              controller.load();
            },
          ),
        ),
        const SizedBox(width: AppDesign.spaceS),
        Expanded(
          child: _entryCard(
            context,
            icon: Icons.person_add_alt_outlined,
            label: '好友申请',
            badgeStream: socket.unread,
            badgeSelector: (u) => u.friendRequests,
            onTap: () async {
              await Get.to(() => FriendRequestsPage());
              controller.load();
            },
          ),
        ),
        const SizedBox(width: AppDesign.spaceS),
        Expanded(
          child: _entryCard(
            context,
            icon: Icons.notifications_none,
            label: '通知',
            badgeStream: socket.unread,
            badgeSelector: (u) => u.notifications,
            onTap: () async {
              await Get.to(() => NotificationsPage());
              controller.load();
            },
          ),
        ),
      ],
    );
  }

  Widget _entryCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Rx<UnreadSummary>? badgeStream,
    int Function(UnreadSummary)? badgeSelector,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget iconBlock = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Icon(icon, size: 22, color: scheme.onPrimaryContainer),
    );
    if (badgeStream != null && badgeSelector != null) {
      iconBlock = Stack(
        clipBehavior: Clip.none,
        children: [
          iconBlock,
          Positioned(
            right: -4,
            top: -4,
            child: Obx(() => ChatBadge(count: badgeSelector(badgeStream.value))),
          ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.appCardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusL),
        border: Border.all(color: context.appBorderColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesign.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceM),
            child: Column(
              children: [
                iconBlock,
                const SizedBox(height: AppDesign.spaceXS),
                Text(label, style: text.labelMedium?.copyWith(color: scheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 群会话条目：群图标 + 群名/成员数 + 最后一条消息 + 未读徽标。
  Widget _groupTile(BuildContext context, ChatGroup g) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        onTap: () => _openEntry(context, g),
        child: Row(
          children: [
            GroupAvatar(groupId: g.groupId),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: AppDesign.spaceXS),
                      Text(
                        ChatTimeFmt.shortTime(g.lastMessageAt),
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesign.spaceXXXS),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.lastMessage.isEmpty
                              ? '${g.memberCount}人 · 暂无消息'
                              // 摘要去 Markdown 标记，避免列表里出现 **粗体**、$x^2$ 源码。
                              : ChatMarkdown.strip(g.lastMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (g.unreadCount > 0) ...[
                        const SizedBox(width: AppDesign.spaceXS),
                        ChatBadge(count: g.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationTile(BuildContext context, Friend f) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        onTap: () => _openEntry(context, f),
        child: Row(
          children: [
            ChatAvatar(
              userId: f.userId,
              name: f.displayName,
              hasAvatar: f.hasAvatar,
              avatarUpdatedAt: f.avatarUpdatedAt,
              onTap: () => Get.to(() => UserProfilePage(userId: f.userId)),
            ),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: AppDesign.spaceXS),
                      Text(
                        ChatTimeFmt.shortTime(f.lastMessageAt),
                        style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesign.spaceXXXS),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.lastMessage.isEmpty ? '暂无消息' : ChatMarkdown.strip(f.lastMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (f.unreadCount > 0) ...[
                        const SizedBox(width: AppDesign.spaceXS),
                        ChatBadge(count: f.unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
