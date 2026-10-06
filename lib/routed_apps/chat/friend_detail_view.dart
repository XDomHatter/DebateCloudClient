import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/group_chat_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 好友详情页（私聊页右上角入口，非个人主页）。
///
/// 仅展示对方简短信息（头像、昵称、用户名、在线态），并提供
/// 「设置备注」与「共同群聊」两个功能区块。
class FriendDetailPage extends StatefulWidget {
  final Friend friend;

  const FriendDetailPage({super.key, required this.friend});

  @override
  State<FriendDetailPage> createState() => _FriendDetailPageState();
}

class _FriendDetailPageState extends State<FriendDetailPage> {
  late final FriendDetailController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(FriendDetailController(widget.friend.userId));
    // 备注保存成功后回写会话对象，私聊页标题（displayName）随之更新。
    controller.onRemarkSaved = (remark) {
      widget.friend.remark = remark;
      setState(() {});
      // 私聊页标题即时跟随（订阅 remark 的 Obx 会重建）。
      try {
        Get.find<ChatDetailController>().remark.value = remark;
      } catch (_) {}
      // 会话列表展示名同样按「备注优先」回读服务端数据。
      try {
        Get.find<ChatHomeController>().load();
      } catch (_) {}
      AppSnackbar.show('提示', remark.isEmpty ? '备注已清空' : '备注已保存');
    };
  }

  @override
  void dispose() {
    Get.delete<FriendDetailController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppPageScaffold(
          title: '好友详情',
          loadingState: AppLoading(),
        );
      }
      final d = controller.detail.value;
      if (d == null) {
        return AppPageScaffold(
          title: '好友详情',
          maxWidth: AppDesign.maxReadingWidth,
          children: [
            AppEmptyState(
              icon: Icons.person_off_outlined,
              message: controller.errorMessage.value.isEmpty
                  ? '加载失败'
                  : controller.errorMessage.value,
              actionLabel: '重试',
              onAction: controller.load,
            ),
          ],
        );
      }
      return AppPageScaffold(
        title: '好友详情',
        maxWidth: AppDesign.maxReadingWidth,
        children: [
          _profileCard(context, d),
          const SizedBox(height: AppDesign.spaceM),
          _remarkCard(context, d),
          const SizedBox(height: AppDesign.spaceM),
          _commonGroupsCard(context, d),
        ],
      );
    });
  }

  /// 简短资料卡：头像 + 展示名 + 用户名 + 在线态。
  ///
  /// 布局与群信息页 _profileCard 同构（头像在左、文案在右、AppMetaRow 明细行），
  /// 头像右下角的状态圆点替代独立芯片，整卡观感与「群信息」一致。
  Widget _profileCard(BuildContext context, ChatFriendDetail d) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ChatAvatar(
                      userId: d.friend.userId,
                      name: widget.friend.displayName,
                      hasAvatar: d.friend.hasAvatar,
                      avatarUpdatedAt: d.friend.avatarUpdatedAt,
                      radius: 26,
                    ),
                    // 在线态角标：语义色绿点 = 在线，灰点 = 离线。
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: d.online
                              ? context.statusStyleOf(AppStatus.success).foreground
                              : scheme.outlineVariant,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.appCardColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppDesign.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.friend.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppDesign.spaceXXXS),
                      Text(
                        '用户名：${d.friend.username}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: AppDesign.spaceL),
            AppMetaRow(
              icon: Icons.badge_outlined,
              label: '昵称',
              value: widget.friend.originalName,
            ),
            AppMetaRow(
              icon: Icons.edit_note_outlined,
              label: '备注',
              value: d.remark.isEmpty ? '未设置' : d.remark,
            ),
          ],
        ),
      ),
    );
  }

  /// 操作卡：「设置备注」入口行（AppCard + ListTile，与全站列表操作一致）。
  Widget _remarkCard(BuildContext context, ChatFriendDetail d) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final hasRemark = d.remark.isNotEmpty;
    return AppCard(
      child: ListTile(
        leading: const Icon(Icons.edit_note_outlined),
        title: const Text('设置备注'),
        subtitle: Text(
          hasRemark ? d.remark : '仅自己可见',
          style: text.bodyMedium?.copyWith(
            color: hasRemark ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: () => _showRemarkDialog(d.remark),
      ),
    );
  }

  /// 共同群聊卡：双方均为成员的群；点击进入群聊。
  Widget _commonGroupsCard(BuildContext context, ChatFriendDetail d) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceXS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesign.spaceM,
              AppDesign.spaceS,
              AppDesign.spaceM,
              AppDesign.spaceXXS,
            ),
            child: Row(
              children: [
                Icon(Icons.groups_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: AppDesign.spaceXS),
                Text(
                  '共同群聊（${d.commonGroups.length}）',
                  style: text.titleSmall?.copyWith(color: scheme.onSurface),
                ),
              ],
            ),
          ),
          if (d.commonGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.spaceM,
                AppDesign.spaceXS,
                AppDesign.spaceM,
                AppDesign.spaceM,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppDesign.spaceXS),
                  Text(
                    '暂无共同群聊',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final g in d.commonGroups)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesign.spaceM,
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppDesign.radiusM),
                  ),
                  child: Icon(
                    Icons.groups_2,
                    size: 22,
                    color: scheme.primary,
                  ),
                ),
                title: Text(g.name),
                subtitle: Text('${g.memberCount} 人'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Get.to(() => GroupChatPage(group: g)),
              ),
        ],
      ),
    );
  }

  void _showRemarkDialog(String current) {
    final ctrl = TextEditingController(text: current);
    Get.dialog(
      AppDialog(
        title: '设置备注',
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '输入备注（留空则清空）',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          Obx(
            () => FilledButton(
              onPressed: controller.isSavingRemark.value
                  ? null
                  : () async {
                      final ok = await controller.saveRemark(ctrl.text);
                      if (ok) Get.back();
                    },
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
