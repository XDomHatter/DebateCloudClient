import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/group_invite_view.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 群聊信息页：群资料（群名/群主/创建时间）+ 成员列表。
/// 群主可见"添加成员""移出成员""解散群聊"；普通成员可"退出群聊"。
class GroupInfoPage extends StatefulWidget {
  final int groupId;

  const GroupInfoPage({super.key, required this.groupId});

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late final GroupInfoController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(GroupInfoController(widget.groupId));
  }

  @override
  void dispose() {
    Get.delete<GroupInfoController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('群聊信息')),
      body: Obx(() {
        final info = controller.info.value;
        if (info == null) {
          if (controller.errorMessage.value.isNotEmpty) {
            return AppEmptyState(
              icon: Icons.wifi_off_outlined,
              message: controller.errorMessage.value,
              actionLabel: '重试',
              onAction: controller.load,
            );
          }
          return const AppLoading();
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
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
                      _profileCard(context, info),
                      const SizedBox(height: AppDesign.spaceL),
                      _memberSectionHeader(context, info),
                      const SizedBox(height: AppDesign.spaceS),
                      for (final m in info.members)
                        _memberTile(context, m),
                      const SizedBox(height: AppDesign.spaceL),
                      _bottomAction(context),
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

  /// 群资料卡：群名、群主、创建时间、成员数——对所有成员可见。
  Widget _profileCard(BuildContext context, ChatGroupInfo info) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        child: Column(
          children: [
            Row(
              children: [
                GroupAvatar(groupId: info.groupId, radius: 26),
                const SizedBox(width: AppDesign.spaceM),
                Expanded(
                  child: Text(
                    info.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: AppDesign.spaceL),
            AppMetaRow(
              icon: Icons.verified_user_outlined,
              label: '群主',
              value: info.ownerDisplayName,
            ),
            AppMetaRow(
              icon: Icons.event_outlined,
              label: '创建时间',
              value: _fullTime(info.createdAt),
            ),
            AppMetaRow(
              icon: Icons.people_outline,
              label: '成员数',
              value: '${info.memberCount}',
            ),
          ],
        ),
      ),
    );
  }

  String _fullTime(String createdAt) {
    final date = ChatTimeFmt.dateLabel(createdAt);
    final time = ChatTimeFmt.bubbleTime(createdAt);
    return time.isEmpty ? (date.isEmpty ? '—' : date) : '$date $time';
  }

  Widget _memberSectionHeader(BuildContext context, ChatGroupInfo info) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '成员（${info.memberCount}）',
          style: text.titleSmall?.copyWith(color: scheme.onSurface),
        ),
        const Spacer(),
        if (controller.isOwner)
          // 注意：全站按钮主题的 minimumSize 是 Size.fromHeight（宽度为无穷大），
          // Row 主轴不约束子项，裸按钮会拿到 w=Infinity 的紧约束而崩坏；
          // 这里显式给有限宽度（同 ChatSmallButton 的做法）。
          TextButton.icon(
            onPressed: _addMembers,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('添加成员'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppDesign.controlHeight),
              padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceM),
            ),
          ),
      ],
    );
  }

  Widget _memberTile(BuildContext context, ChatGroupMember m) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canKick = controller.isOwner && !m.isOwner;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.spaceXS),
      child: AppCard(
        padding: const EdgeInsets.all(AppDesign.spaceS),
        child: Row(
          children: [
            ChatAvatar(
              userId: m.userId,
              name: m.displayName,
              hasAvatar: m.hasAvatar,
              avatarUpdatedAt: m.avatarUpdatedAt,
              online: m.online,
              onTap: () => Get.to(() => UserProfilePage(userId: m.userId)),
            ),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Text(
                m.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: scheme.onSurface),
              ),
            ),
            if (m.isOwner) ...[
              const SizedBox(width: AppDesign.spaceXS),
              const OwnerChip(),
            ],
            if (canKick)
              AppTooltip(
                message: '移出群聊',
                child: IconButton(
                  onPressed: () => _confirmKick(m),
                  icon: Icon(Icons.remove_circle_outline,
                      size: 20, color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomAction(BuildContext context) {
    final isOwner = controller.isOwner;
    return Obx(() {
      final busy = controller.isWorking.value;
      return FilledButton.tonalIcon(
        onPressed: busy ? null : (isOwner ? _confirmDisband : _confirmLeave),
        icon: Icon(
          isOwner ? Icons.delete_forever_outlined : Icons.logout,
          color: Theme.of(context).colorScheme.error,
        ),
        label: Text(isOwner ? '解散群聊' : '退出群聊'),
        style: FilledButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          minimumSize: const Size.fromHeight(48),
        ),
      );
    });
  }

  Future<void> _addMembers() async {
    final existing = controller.info.value?.members
            .map((m) => m.userId)
            .toSet() ??
        <int>{};
    await Get.to<void>(() => GroupInvitePage(
          groupId: widget.groupId,
          existingIds: existing,
        ));
    // 拉人完成后刷新成员列表。
    controller.load();
  }

  Future<void> _confirmKick(ChatGroupMember m) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('移出成员'),
        content: Text('确定将 ${m.displayName} 移出群聊吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back<bool>(result: true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (ok == true) controller.kick(m);
  }

  Future<void> _confirmLeave() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后将不再接收该群消息，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back<bool>(result: true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true) {
      // 成功时页面导航由 group.updated 事件驱动（见控制器），这里只提示。
      final left = await controller.leave();
      if (left) AppSnackbar.success('已退出', '你已退出群聊');
    }
  }

  Future<void> _confirmDisband() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('解散群聊'),
        content: const Text('解散后所有成员与聊天记录都会删除，确定解散吗？'),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Get.back<bool>(result: true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final done = await controller.disband();
      if (done) AppSnackbar.success('已解散', '群聊已解散');
    }
  }
}
