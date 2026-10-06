import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/group_info_view.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/chat_clipboard.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 群聊窗口：与 ChatDetailPage 同骨架（reverse 消息列表 + 底部输入栏），
/// 气泡为他人消息增加发送者昵称与头像，AppBar 提供群信息入口。
class GroupChatPage extends StatefulWidget {
  final ChatGroup group;

  const GroupChatPage({super.key, required this.group});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  late final GroupChatController controller;
  final inputCtrl = TextEditingController();
  final inputFocus = FocusNode();
  final scrollCtrl = ScrollController();
  Worker? _msgWorker;

  @override
  void initState() {
    super.initState();
    controller = Get.put(GroupChatController(widget.group));
    // 接近底部时收到新消息自动滚到最新；翻页加载不触发（此时在顶部）。
    _msgWorker = ever(controller.messages, (_) => _maybeScrollToBottom());
    scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _msgWorker?.dispose();
    scrollCtrl.removeListener(_onScroll);
    inputCtrl.dispose();
    inputFocus.dispose();
    scrollCtrl.dispose();
    Get.delete<GroupChatController>();
    super.dispose();
  }

  /// 翻页：接近列表顶部（视觉最旧端）时加载更早消息。
  void _onScroll() {
    if (!scrollCtrl.hasClients) return;
    if (scrollCtrl.position.pixels >=
        scrollCtrl.position.maxScrollExtent - 300) {
      controller.loadMore();
    }
  }

  void _maybeScrollToBottom() {
    if (!scrollCtrl.hasClients) return;
    if (scrollCtrl.position.pixels < 300) {
      scrollCtrl.animateTo(
        0,
        duration: AppDesign.normal,
        curve: Curves.easeOut,
      );
    }
  }

  /// 发送消息。焦点必须留在输入框——框架在桌面端会主动失焦
  /// （Enter 提交走 `_finalizeEditing`，点按钮走 `onTapOutside`），
  /// 这里作为兜底再抢回一次，避免用户每次发送都要重新点输入框。
  void _submit() {
    controller.send(inputCtrl.text);
    inputCtrl.clear();
    inputFocus.requestFocus();
  }

  /// 选好媒体后先读出图片尺寸再上传：接收端据此按比例占位，
  /// 图片解码完成前列表高度不会跳动。
  Future<void> _pickMedia(XFile file, bool isVideo) async {
    var width = 0;
    var height = 0;
    if (!isVideo) {
      try {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        width = frame.image.width;
        height = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (_) {
        // 读取失败就不上报尺寸，接收端按 4:3 兜底。
      }
    }
    if (!mounted) return;
    await controller.sendMedia(
      file,
      isVideo: isVideo,
      width: width,
      height: height,
    );
  }

  Future<void> _openInfo() async {
    await Get.to<void>(() => GroupInfoPage(groupId: widget.group.groupId));
    // 信息页里可能发生退群/解散/被踢等，返回后重拉一次校准状态。
    controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GroupAvatar(groupId: widget.group.groupId, radius: 14),
            const SizedBox(width: AppDesign.spaceS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Obx(() {
                    return Text(
                      '${controller.memberCount.value}人',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
        actions: [
          AppTooltip(
            message: '群聊信息',
            child: IconButton(
              onPressed: _openInfo,
              icon: const Icon(Icons.info_outline),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const AppSkeletonChat();
        }
        if (controller.errorMessage.value.isNotEmpty) {
          return AppEmptyState(
            icon: Icons.wifi_off_outlined,
            title: '加载失败',
            message: controller.errorMessage.value,
            hint: '历史消息需要服务器连接',
            actionLabel: '重试',
            onAction: controller.load,
          );
        }
        return Column(
          children: [
            _connectionBanner(context),
            Expanded(child: _messageList(context)),
            Divider(height: 1, color: scheme.outlineVariant),
            _inputBar(context),
          ],
        );
      }),
    );
  }

  /// WebSocket 断线提示条：业务收发走 HTTP 不受影响，但实时推送暂停。
  Widget _connectionBanner(BuildContext context) {
    final socket = Get.find<ChatSocket>();
    return Obx(() {
      final status = socket.status.value;
      if (status == ChatConnStatus.connected) return const SizedBox.shrink();
      final style = context.statusStyleOf(AppStatus.warning);
      return Material(
        color: style.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.spaceM,
            vertical: AppDesign.spaceXS,
          ),
          child: Row(
            children: [
              if (status == ChatConnStatus.connecting)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: style.foreground,
                  ),
                )
              else
                Icon(Icons.wifi_off, size: 14, color: style.foreground),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: Text(
                  status == ChatConnStatus.connecting
                      ? '正在连接服务器…'
                      : '连接已断开，正在自动重连…',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: style.foreground),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// reverse ListView：offset 0 锚定最新消息（视觉底部），向上翻历史。
  Widget _messageList(BuildContext context) {
    final messages = controller.messages;
    if (messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline,
        message: '暂无消息，跟大家打个招呼吧',
        verticalPadding: AppDesign.spaceL,
      );
    }
    final itemCount = messages.length + (controller.hasMore ? 1 : 0);
    return ListView.builder(
      controller: scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceM),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // 视觉最顶部（最旧消息之上）：加载更早消息的指示器。
        if (controller.hasMore && index == itemCount - 1) {
          return Obx(() {
            if (!controller.isLoadingMore.value) {
              return const SizedBox(height: AppDesign.spaceXL);
            }
            return const Padding(
              padding: EdgeInsets.all(AppDesign.spaceM),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          });
        }
        final m = messages[index];
        // 与更早一条（desc 列表中的下一条）不同天，则在视觉上方插日期分隔。
        final showDate = index == messages.length - 1 ||
            ChatTimeFmt.dateKey(m.createdAt) !=
                ChatTimeFmt.dateKey(messages[index + 1].createdAt);
        return Column(
          children: [
            if (showDate) _dateSeparator(context, m.createdAt),
            _messageItem(context, m),
          ],
        );
      },
    );
  }

  Widget _messageItem(BuildContext context, ChatMessage m) {
    return switch (m.type) {
      'system' => _systemLine(context, m),
      'image' || 'video' => _mediaMessage(context, m),
      _ => _bubble(context, m),
    };
  }

  /// 图片 / 视频消息：媒体本体替换文本气泡，他人消息同样带发送者昵称与头像。
  Widget _mediaMessage(BuildContext context, ChatMessage m) {
    final isMe = m.senderId == controller.myId;
    final member = controller.members[m.senderId];
    final senderName =
        member?.displayName ?? (m.senderId > 0 ? '#${m.senderId}' : '');
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.6)
        .clamp(160.0, 320.0);

    final content = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && senderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4),
            child: Text(
              senderName,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ChatMediaBubble(message: m, maxWidth: maxWidth),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            ChatTimeFmt.bubbleTime(m.createdAt),
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceXXS,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            ChatAvatar(
              userId: m.senderId,
              name: senderName,
              hasAvatar: member?.hasAvatar ?? false,
              avatarUpdatedAt: member?.avatarUpdatedAt,
              radius: 15,
              onTap: () => Get.to(() => UserProfilePage(userId: m.senderId)),
            ),
            const SizedBox(width: AppDesign.spaceXS),
          ],
          Flexible(child: content),
        ],
      ),
    );
  }

  Widget _dateSeparator(BuildContext context, String createdAt) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceS),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppDesign.radiusFull),
          ),
          child: Text(
            ChatTimeFmt.dateLabel(createdAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage m) {
    // 群聊必须用真实 userId 区分自己/他人。
    final isMe = m.senderId == controller.myId;
    final member = controller.members[m.senderId];
    final senderName =
        member?.displayName ?? (m.senderId > 0 ? '#${m.senderId}' : '');
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxBubbleWidth = (MediaQuery.sizeOf(context).width * 0.72)
        .clamp(240.0, 560.0);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceS,
      ),
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      decoration: BoxDecoration(
        color: isMe ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppDesign.radiusL),
          topRight: Radius.circular(AppDesign.radiusL),
          bottomLeft: Radius.circular(isMe
              ? AppDesign.radiusL
              : AppDesign.radiusS),
          bottomRight: Radius.circular(isMe
              ? AppDesign.radiusS
              : AppDesign.radiusL),
        ),
      ),
      child: ChatRichText(
        m.content,
        style: text.bodyMedium?.copyWith(
          color: isMe ? scheme.onPrimaryContainer : scheme.onSurface,
        ),
      ),
    );

    final content = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && senderName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4),
            child: Text(
              senderName,
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        // 复制入口包在气泡最外层：超 600 字折叠态不挂载 GptMarkdown，
        // 放进 ChatRichText 内部就够不着全文了。
        ChatCopyWrapper(
          content: m.content,
          bubbleColor:
              isMe ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: bubble,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            ChatTimeFmt.bubbleTime(m.createdAt),
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceXXS,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            ChatAvatar(
              userId: m.senderId,
              name: senderName,
              hasAvatar: member?.hasAvatar ?? false,
              avatarUpdatedAt: member?.avatarUpdatedAt,
              radius: 15,
              onTap: () => Get.to(() => UserProfilePage(userId: m.senderId)),
            ),
            const SizedBox(width: AppDesign.spaceXS),
          ],
          Flexible(child: content),
        ],
      ),
    );
  }

  /// 系统提示消息：居中弱化展示，不进入气泡流。
  Widget _systemLine(BuildContext context, ChatMessage m) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceXS,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppDesign.radiusFull),
          ),
          child: Text(
            m.content,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }

  Widget _inputBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spaceM,
          vertical: AppDesign.spaceS,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 附件按钮属于输入区：包在 chatInputTapGroupId 分组内，
            // 桌面端点它不会把焦点从输入框抢走。
            Obx(
              () => ChatMediaPickerButton(
                enabled: true,
                isUploading: controller.isUploading.value,
                onPicked: _pickMedia,
              ),
            ),
            const SizedBox(width: AppDesign.spaceXS),
            Expanded(
              child: ChatInputField(
                controller: inputCtrl,
                focusNode: inputFocus,
                onSubmitted: _submit,
                // 桌面端进入会话即聚焦输入框，可直接打字；移动端会弹软键盘，不自动聚焦。
                autofocus: !ChatInputField.isMobilePlatform,
              ),
            ),
            const SizedBox(width: AppDesign.spaceS),
            // 文本为空时禁用发送，避免发出空消息。
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: inputCtrl,
              builder: (context, value, _) {
                // 与输入框同组：点发送按钮不算「输入框外点击」，不会丢焦点。
                return TextFieldTapRegion(
                  groupId: chatInputTapGroupId,
                  child: AppTooltip(
                    message: '发送',
                    child: IconButton.filled(
                      onPressed: value.text.trim().isEmpty ? null : _submit,
                      icon: const Icon(Icons.send),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
