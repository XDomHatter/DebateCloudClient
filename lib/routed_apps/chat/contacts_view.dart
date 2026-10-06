import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_detail_view.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/friend_requests_view.dart';
import 'package:debate_cloud/routed_apps/chat/group_create_view.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 好友列表 + 搜索添加好友。
class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  late final ContactsController controller;
  final searchCtrl = TextEditingController();

  /// 是否已执行过一次有效搜索，用于区分「没搜过」和「搜不到」。
  bool searched = false;

  @override
  void initState() {
    super.initState();
    controller = Get.put(ContactsController());
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    Get.delete<ContactsController>();
    super.dispose();
  }

  void _submitSearch() {
    final keyword = searchCtrl.text.trim();
    if (keyword.isEmpty) {
      setState(() => searched = false);
      controller.searchResults.clear();
      return;
    }
    setState(() => searched = true);
    controller.search(keyword);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('好友'),
        actions: [_groupAction(), _requestsAction()],
      ),
      body: Obx(() {
        // 只有首屏骨架加载才全屏转圈，刷新时保持列表可见。
        if (controller.isLoading.value && controller.friends.isEmpty) {
          return const AppLoading();
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
                      _searchBar(context),
                      if (controller.errorMessage.value.isNotEmpty) ...[
                        const SizedBox(height: AppDesign.spaceS),
                        _errorBanner(context),
                      ],
                      if (searched) ...[
                        const SizedBox(height: AppDesign.spaceL),
                        _searchSection(context),
                      ],
                      const SizedBox(height: AppDesign.spaceL),
                      _friendsSection(context),
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

  /// AppBar 上的"发起群聊"入口。
  Widget _groupAction() {
    return AppTooltip(
      message: '发起群聊',
      child: IconButton(
        onPressed: () async {
          await Get.to(() => GroupCreatePage());
          // 创建成功后群会话立即可用，刷新好友列表保持数据新鲜。
          controller.load();
        },
        icon: const Icon(Icons.group_add_outlined),
      ),
    );
  }

  /// AppBar 上的好友申请入口，带未读红点。
  Widget _requestsAction() {
    final socket = Get.find<ChatSocket>();
    return Obx(() {
      final n = socket.unread.value.friendRequests;
      return AppTooltip(
        message: '好友申请',
        child: IconButton(
          onPressed: () async {
            await Get.to(() => FriendRequestsPage());
            // 处理完申请后好友列表可能已变化。
            controller.load();
          },
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            // 跟随主题 error / onError，不写死红色（深色模式下需要提亮）。
            backgroundColor: Theme.of(context).colorScheme.error,
            child: const Icon(Icons.person_add_alt_outlined),
          ),
        ),
      );
    });
  }

  Widget _searchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索用户名或昵称',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: searchCtrl,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return AppTooltip(
                    message: '清空',
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        searchCtrl.clear();
                        setState(() => searched = false);
                        controller.searchResults.clear();
                      },
                    ),
                  );
                },
              ),
            ),
            onSubmitted: (_) => _submitSearch(),
          ),
        ),
        const SizedBox(width: AppDesign.spaceS),
        // 固定宽度，避免搜索中切换成加载指示器时布局跳动。
        SizedBox(
          width: 88,
          height: AppDesign.controlHeight,
          child: Obx(
            () => FilledButton(
              onPressed: controller.isSearching.value ? null : _submitSearch,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: controller.isSearching.value
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Text('搜索'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(BuildContext context) {
    final style = context.statusStyleOf(AppStatus.danger);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceS,
        vertical: AppDesign.spaceXS,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppDesign.radiusM),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: style.foreground),
          const SizedBox(width: AppDesign.spaceXS),
          Expanded(
            child: Text(
              controller.errorMessage.value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: style.foreground),
            ),
          ),
          TextButton(
            onPressed: controller.load,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _searchSection(BuildContext context) {
    final results = controller.searchResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: '搜索结果',
          icon: Icons.search,
          trailing: Text(
            '${results.length} 人',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: AppDesign.spaceXS),
        if (controller.isSearching.value)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppDesign.spaceM),
            child: AppLoading(),
          )
        else if (results.isEmpty)
          const AppEmptyState(
            icon: Icons.person_search_outlined,
            message: '没有找到匹配的用户，换个用户名或昵称试试',
            verticalPadding: AppDesign.spaceL,
          )
        else
          for (final u in results) _userCard(context, u),
      ],
    );
  }

  Widget _userCard(BuildContext context, ChatUserBrief u) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        child: Row(
          children: [
            ChatAvatar(
              userId: u.userId,
              name: u.displayName,
              hasAvatar: u.hasAvatar,
              avatarUpdatedAt: u.avatarUpdatedAt,
              onTap: () => Get.to(() => UserProfilePage(userId: u.userId)),
            ),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppDesign.spaceXXXS),
                  ChatSubLine('用户名：${u.username}'),
                ],
              ),
            ),
            const SizedBox(width: AppDesign.spaceXS),
            if (u.isFriend)
              const AppStatusChip(label: '已是好友', status: AppStatus.neutral)
            else if (u.requestSent)
              const AppStatusChip(label: '已发送', status: AppStatus.info)
            else
              ChatSmallButton(
                label: '加好友',
                icon: Icons.person_add_alt_1,
                onPressed: () async {
                  final ok = await controller.sendRequest(u.userId);
                  if (ok && context.mounted) {
                    AppSnackbar.success('已发送', '等待对方通过好友申请');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _friendsSection(BuildContext context) {
    final friends = controller.friends;
    final onlineCount = friends.where((f) => f.online).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: '我的好友',
          icon: Icons.people_outline,
          trailing: Text(
            friends.isEmpty ? '' : '$onlineCount 人在线 · 共 ${friends.length} 人',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: AppDesign.spaceXS),
        if (friends.isEmpty)
          const AppEmptyState(
            icon: Icons.people_outline,
            message: '还没有好友，搜索用户名添加吧',
            verticalPadding: AppDesign.spaceL,
          )
        else
          for (final f in _sortedFriends(friends)) _friendCard(context, f),
      ],
    );
  }

  /// 在线优先，其次按名称，保证列表顺序稳定。
  static List<Friend> _sortedFriends(List<Friend> source) {
    final list = [...source];
    list.sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.displayName.compareTo(b.displayName);
    });
    return list;
  }

  Widget _friendCard(BuildContext context, Friend f) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        onTap: () async {
          await Get.to(() => ChatDetailPage(friend: f));
          controller.load();
        },
        child: Row(
          children: [
            ChatAvatar(
              userId: f.userId,
              name: f.displayName,
              hasAvatar: f.hasAvatar,
              avatarUpdatedAt: f.avatarUpdatedAt,
              online: f.online,
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
                          style: text.titleSmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (f.unreadCount > 0) ...[
                        const SizedBox(width: AppDesign.spaceXS),
                        ChatBadge(count: f.unreadCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppDesign.spaceXXXS),
                  ChatPresenceLine(
                    online: f.online,
                    trailingText: f.lastMessage,
                  ),
                ],
              ),
            ),
            AppTooltip(
              message: '更多操作',
              child: PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'chat') Get.to(() => ChatDetailPage(friend: f));
                  if (value == 'delete') _confirmDelete(context, f);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'chat',
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 18),
                        SizedBox(width: AppDesign.spaceXS),
                        Text('发消息'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                          color:
                              context.statusStyleOf(AppStatus.danger).foreground,
                        ),
                        const SizedBox(width: AppDesign.spaceXS),
                        Text(
                          '删除好友',
                          style: TextStyle(
                            color: context
                                .statusStyleOf(AppStatus.danger)
                                .foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Friend f) {
    Get.dialog(
      AppDialog(
        title: '删除好友',
        content: Text('确定删除好友「${f.displayName}」吗？聊天记录将保留。'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.statusStyleOf(AppStatus.danger).foreground,
            ),
            onPressed: () async {
              Get.back();
              try {
                await ChatSDK.deleteFriend(
                  Get.find<AuthService>().userObj.value,
                  f.userId,
                );
                await controller.load();
                AppSnackbar.success('已删除', '已移除好友「${f.displayName}」');
              } catch (e) {
                AppSnackbar.error(
                  '删除失败',
                  e is ApiException ? e.message : '请检查服务器连接',
                );
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
