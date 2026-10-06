import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/group_chat_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 创建群聊：自定义群名 + 从好友列表勾选初始成员（创建者自动成为群主）。
class GroupCreatePage extends StatefulWidget {
  const GroupCreatePage({super.key});

  @override
  State<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends State<GroupCreatePage> {
  late final GroupCreateController controller;
  final nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = Get.put(GroupCreateController());
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    Get.delete<GroupCreateController>();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = nameCtrl.text.trim();
    final groupId = await controller.create(name);
    if (groupId <= 0 || !mounted) return;
    // 关闭创建页并直接进入新群聊。
    Get.back<void>();
    final auth = Get.find<AuthService>();
    Get.to<void>(() => GroupChatPage(
          group: ChatGroup(
            groupId: groupId,
            name: name,
            ownerId: auth.userProfile.value?.userId ?? 0,
            createdAt: '',
            memberCount: controller.selected.length + 1,
            unreadCount: 0,
            lastMessage: '',
            lastMessageAt: '',
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('发起群聊')),
      body: Obx(() {
        if (controller.isLoading.value && controller.friends.isEmpty) {
          return const AppLoading();
        }
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
                    Text('群名称', style: text.titleSmall),
                    const SizedBox(height: AppDesign.spaceS),
                    TextField(
                      controller: nameCtrl,
                      maxLength: 50,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        hintText: '给群聊起个名字',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppDesign.spaceL),
                    Row(
                      children: [
                        Text('选择初始成员', style: text.titleSmall),
                        const SizedBox(width: AppDesign.spaceS),
                        Obx(() {
                          final n = controller.selected.length;
                          return Text(
                            n > 0 ? '已选 $n 人' : '可多选，也可创建后再拉人',
                            style: text.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
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
                    else
                      // 不再包 Obx：列表内容由外层 body Obx 驱动刷新，
                      // 勾选状态由 FriendCheckList 行内的 Checkbox Obx 驱动，
                      // 此处的闭包没有同步读取 observable，包了会触发 GetX 断言。
                      AppCard(
                        child: FriendCheckList(
                          friends: controller.friends,
                          selected: controller.selected,
                          onToggle: controller.toggle,
                        ),
                      ),
                    const SizedBox(height: AppDesign.spaceL),
                    Obx(() {
                      return FilledButton(
                        onPressed:
                            controller.isCreating.value ? null : _submit,
                        child: Text(controller.isCreating.value
                            ? '创建中…'
                            : '创建群聊'),
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
