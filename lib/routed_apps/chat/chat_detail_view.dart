import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/models/chat/controller.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/chat/friend_detail_view.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/chat_clipboard.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 一对一聊天窗口。
class ChatDetailPage extends StatefulWidget {
  final Friend friend;

  const ChatDetailPage({super.key, required this.friend});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  late final ChatDetailController controller;
  final inputCtrl = TextEditingController();
  final inputFocus = FocusNode();
  final scrollCtrl = ScrollController();
  Worker? _msgWorker;

  @override
  void initState() {
    super.initState();
    controller = Get.put(ChatDetailController(widget.friend));
    // 接近底部时收到新消息自动滚到最新；翻页加载不触发（此时在顶部）。
    _msgWorker = ever(controller.messages, (_) => _maybeScrollToBottom());
    // 接近顶部（最旧消息端）时翻页加载更早历史。
    scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _msgWorker?.dispose();
    scrollCtrl.removeListener(_onScroll);
    inputCtrl.dispose();
    inputFocus.dispose();
    scrollCtrl.dispose();
    Get.delete<ChatDetailController>();
    super.dispose();
  }

  /// 翻页：接近列表顶部（视觉最旧端）时加载更早消息。
  /// loadMore 内部有 _hasMore/isLoadingMore 防抖，重复触发无副作用。
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
  /// 图片解码完成前列表高度不会跳动。视频尺寸由播放器初始化时自行获知。
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          // 好友详情（简短资料 / 备注 / 共同群聊）。
          AppTooltip(
            message: '好友详情',
            child: IconButton(
              icon: const Icon(Icons.person_search_outlined),
              onPressed: () =>
                  Get.to(() => FriendDetailPage(friend: widget.friend)),
            ),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 订阅 remark：在好友详情页改完备注回来，标题立即更新。
            Obx(() => Text(
                  controller.remark.value.isEmpty
                      ? widget.friend.displayName
                      : controller.remark.value,
                )),
            Obx(() {
              final online = controller.online.value;
              final color = online
                  ? context.statusStyleOf(AppStatus.success).foreground
                  : scheme.onSurfaceVariant;
              return Text(
                online ? '在线' : '离线',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              );
            }),
          ],
        ),
      ),
      body: Obx(() {
        // 首屏用气泡骨架，避免进入会话时先转圈再整页跳成消息流。
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

  /// reverse ListView：offset 0 锚定最新消息（视觉底部），向上翻历史，
  /// 打开页面即自动定位在最下方最新消息，无需手动滚动。
  Widget _messageList(BuildContext context) {
    final messages = controller.messages;
    if (messages.isEmpty) {
      return const AppEmptyState(
        icon: Icons.chat_bubble_outline,
        message: '暂无消息，打个招呼吧',
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
        return ChatMessageTile(
          // 按 key 复用元素：新消息插入时已有项不重建，长消息的折叠
          // 展开状态也因此得以保留。
          key: ValueKey('msg-${m.id}'),
          message: m,
          showDate: showDate,
          builder: (context) => Column(
            children: [
              if (showDate) _dateSeparator(context, m.createdAt),
              _messageItem(context, m),
            ],
          ),
        );
      },
    );
  }

  /// 按消息类型分发渲染：普通文本走气泡，队伍邀请走卡片，系统提示走居中弱化行，
  /// 图片 / 视频走媒体气泡。
  Widget _messageItem(BuildContext context, ChatMessage m) {
    return switch (m.type) {
      'team_invite' => _inviteCard(context, m),
      'system' => _systemLine(context, m),
      'image' || 'video' => _mediaMessage(context, m),
      _ => _bubble(context, m),
    };
  }

  /// 图片 / 视频消息：媒体本体替换文本气泡，头像、时间与已读标记保持一致。
  Widget _mediaMessage(BuildContext context, ChatMessage m) {
    final isMe = m.senderId != widget.friend.userId;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // 媒体比文本窄一些：太宽会把会话压成一条窄缝，且放大后才看得清细节。
    final maxWidth = (MediaQuery.sizeOf(context).width * 0.6)
        .clamp(160.0, 320.0);

    final meta = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ChatTimeFmt.bubbleTime(m.createdAt),
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: AppDesign.spaceXXS),
            // 窄化已读订阅：markRead 只 bump readReceiptTick（不再整表
            // refresh），重绘范围收窄到这个小图标。
            Obx(() {
              controller.readReceiptTick.value;
              return Icon(
                m.read ? Icons.done_all : Icons.done,
                size: 13,
                color: m.read
                    ? context.statusStyleOf(AppStatus.success).foreground
                    : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              );
            }),
          ],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        ChatMediaBubble(message: m, maxWidth: maxWidth),
        meta,
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
              userId: widget.friend.userId,
              name: widget.friend.displayName,
              hasAvatar: widget.friend.hasAvatar,
              avatarUpdatedAt: widget.friend.avatarUpdatedAt,
              radius: 15,
              onTap: () =>
                  Get.to(() => UserProfilePage(userId: widget.friend.userId)),
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
    // 一对一会话中发送者只有好友与自己两种，无需本地 userId。
    final isMe = m.senderId != widget.friend.userId;
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

    final meta = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ChatTimeFmt.bubbleTime(m.createdAt),
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: AppDesign.spaceXXS),
            // 窄化已读订阅：markRead 只 bump readReceiptTick（不再整表
            // refresh），重绘范围收窄到这个小图标。
            Obx(() {
              controller.readReceiptTick.value;
              return Icon(
                m.read ? Icons.done_all : Icons.done,
                size: 13,
                color: m.read
                    ? context.statusStyleOf(AppStatus.success).foreground
                    : scheme.onSurfaceVariant.withValues(alpha: 0.6),
              );
            }),
          ],
        ],
      ),
    );

    final content = Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // 复制入口包在气泡最外层：超 600 字折叠态不挂载 GptMarkdown，
        // 放进 ChatRichText 内部就够不着全文了。
        ChatCopyWrapper(
          content: m.content,
          bubbleColor:
              isMe ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          child: bubble,
        ),
        meta,
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
              userId: widget.friend.userId,
              name: widget.friend.displayName,
              hasAvatar: widget.friend.hasAvatar,
              avatarUpdatedAt: widget.friend.avatarUpdatedAt,
              radius: 15,
              onTap: () =>
                  Get.to(() => UserProfilePage(userId: widget.friend.userId)),
            ),
            const SizedBox(width: AppDesign.spaceXS),
          ],
          Flexible(child: content),
        ],
      ),
    );
  }

  /// 队伍邀请卡片消息。会话对端发送且仍待处理时，展示接受/拒绝操作。
  Widget _inviteCard(BuildContext context, ChatMessage m) {
    final isMe = m.senderId != widget.friend.userId;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxCardWidth = (MediaQuery.sizeOf(context).width * 0.78)
        .clamp(260.0, 560.0);

    final p = m.payload;
    final invitationId = (p['invitationId'] as num?)?.toInt() ?? 0;
    final teamName = (p['teamName'] ?? '') as String;
    final compName = (p['competitionName'] ?? '') as String;
    final inviteType = (p['inviteType'] as num?)?.toInt() ?? 1;
    final note = (p['message'] ?? '') as String;

    // inviteStatuses 在 ListView itemBuilder（布局期）中读取，不在 body Obx
    // 的订阅范围内，必须用局部 Obx 订阅，否则处理后卡片状态不会刷新。
    final card = Obx(() {
      final status = controller.inviteStatuses[invitationId] ?? 0;
      final (statusLabel, statusStyle) = switch (status) {
        1 => ('已接受', AppStatus.success),
        2 => ('已拒绝', AppStatus.danger),
        _ => ('待处理', AppStatus.warning),
      };
      return Container(
      constraints: BoxConstraints(maxWidth: maxCardWidth),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusL),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_2, size: 20, color: scheme.primary),
                const SizedBox(width: AppDesign.spaceXS),
                Expanded(
                  child: Text(
                    '入队邀请',
                    style: text.titleSmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
                AppStatusChip(label: statusLabel, status: statusStyle),
              ],
            ),
            const Divider(height: AppDesign.spaceM + 4),
            AppMetaRow(
              icon: Icons.flag_outlined,
              label: '队伍',
              value: teamName.isEmpty ? '未知队伍' : teamName,
            ),
            if (compName.isNotEmpty)
              AppMetaRow(
                icon: Icons.emoji_events_outlined,
                label: '赛事',
                value: compName,
              ),
            AppMetaRow(
              icon: Icons.badge_outlined,
              label: '角色',
              value: inviteType == 2 ? '教练' : '队员',
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: AppDesign.spaceXXS),
              Text(
                note,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            // 只有被邀请人本人（卡片由会话对端发来）且仍待处理时可以操作。
            if (!isMe && status == 0) ...[
              const SizedBox(height: AppDesign.spaceM),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => controller.respondInvite(m, false),
                      child: const Text('拒绝'),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spaceXS),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => controller.respondInvite(m, true),
                      child: const Text('接受'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceXXS,
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            ChatAvatar(
              userId: widget.friend.userId,
              name: widget.friend.displayName,
              hasAvatar: widget.friend.hasAvatar,
              avatarUpdatedAt: widget.friend.avatarUpdatedAt,
              radius: 15,
              onTap: () =>
                  Get.to(() => UserProfilePage(userId: widget.friend.userId)),
            ),
            const SizedBox(width: AppDesign.spaceXS),
          ],
          Flexible(child: card),
        ],
      ),
    );
  }

  /// 系统提示消息（如邀请处理结果）：居中弱化展示，不进入气泡流。
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
    // 非好友会话（如仅收到邀请卡片）禁止发送普通消息，卡片操作不受影响。
    final canType = widget.friend.isFriend;
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
                enabled: canType,
                isUploading: controller.isUploading.value,
                onPicked: _pickMedia,
              ),
            ),
            const SizedBox(width: AppDesign.spaceXS),
            Expanded(
              child: ChatInputField(
                controller: inputCtrl,
                focusNode: inputFocus,
                enabled: canType,
                hintText: canType ? '输入消息…' : '添加好友后才能发送消息',
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
                final canSend = canType && value.text.trim().isNotEmpty;
                // 与输入框同组：点发送按钮不算「输入框外点击」，不会丢焦点。
                return TextFieldTapRegion(
                  groupId: chatInputTapGroupId,
                  child: AppTooltip(
                    message: '发送',
                    child: IconButton.filled(
                      onPressed: canSend ? _submit : null,
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
