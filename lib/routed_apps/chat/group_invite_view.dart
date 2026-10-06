import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 拉人入群选择页：从好友中勾选尚未入群的用户（仅群主入口，服务端二次校验）。
class GroupInvitePage extends StatefulWidget {
  final int groupId;

  /// 已在群的用户 ID，选择列表中排除。
  final Set<int> existingIds;

  const GroupInvitePage({
    super.key,
    required this.groupId,
    required this.existingIds,
  });

  @override
  State<GroupInvitePage> createState() => _GroupInvitePageState();
}

class _GroupInvitePageState extends State<GroupInvitePage> {
  late final GroupInviteController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(GroupInviteController(
      widget.groupId,
      widget.existingIds,
    ));
  }

  @override
  void dispose() {
    Get.delete<GroupInviteController>();
    super.dispose();
  }

  Future<void> _submit() async {
    final added = await controller.invite();
    if (added >= 0 && mounted) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('添加成员')),
      body: Obx(() {
        if (controller.isLoading.value && controller.friends.isEmpty) {
          return const AppLoading();
        }
        final candidates = controller.candidates;
        return ListView(
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
                    Row(
                      children: [
                        Text('选择要拉入的好友', style: text.titleSmall),
                        const SizedBox(width: AppDesign.spaceS),
                        Obx(() {
                          final n = controller.selected.length;
                          return Text(
                            n > 0 ? '已选 $n 人' : '',
                            style: text.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: AppDesign.spaceS),
                    if (controller.errorMessage.value.isNotEmpty)
                      AppEmptyState(
                        icon: Icons.wifi_off_outlined,
                        message: controller.errorMessage.value,
                        actionLabel: '重试',
                        onAction: controller.load,
                      )
                    else if (candidates.isEmpty)
                      const AppEmptyState(
                        icon: Icons.person_search_outlined,
                        message: '还没有可以拉入的好友',
                        verticalPadding: AppDesign.spaceL,
                      )
                    else
                      // 不再包 Obx：列表内容由外层 body Obx 驱动刷新，
                      // 勾选状态由 FriendCheckList 行内的 Checkbox Obx 驱动，
                      // 此处的闭包没有同步读取 observable，包了会触发 GetX 断言。
                      AppCard(
                        child: FriendCheckList(
                          friends: candidates,
                          selected: controller.selected,
                          onToggle: controller.toggle,
                        ),
                      ),
                    const SizedBox(height: AppDesign.spaceL),
                    Obx(() {
                      return FilledButton(
                        onPressed: controller.selected.isEmpty
                            ? null
                            : _submit,
                        child: const Text('拉入群聊'),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
