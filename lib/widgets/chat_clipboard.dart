import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 聊天气泡的复制能力。
///
/// 三条硬约定，改动前请先读：
///
/// 1. **复制源必须是服务端原样下发的 `ChatMessage.content`**，不能传
///    `ChatMarkdown.prepare()` 的结果——prepare 会把**未配对**的 `$` 转义成
///    `\$`，复制出去会污染原文（`价格 $100` 变成 `价格 \$100`）。
///    富文本是纯客户端的渲染层解释，复制要拿的是「原文」而不是「渲染输入」。
/// 2. **只对文本气泡开放**。媒体消息的 `content` 是 `[图片]` / `[视频]` 占位符，
///    复制无意义；邀请卡片是结构化 payload、系统提示是状态文案，
///    两者按产品决策不提供复制。
/// 3. **复制属于浏览动作**，不要在复制后 `requestFocus()` 抢回输入框焦点——
///    桌面端点气泡本来就会让输入框失焦（`onTapOutside`），这是既有行为，
///    复制不该把它变得更打扰。
abstract final class ChatCopy {
  /// 复制原文：保留 `**粗体**`、`` `code` ``、`$x^2$`、表格与代码围栏等标记。
  ///
  /// 用户明确要求「遇到 Markdown / LaTeX 等内容复制原始文本即可」，
  /// 所以这里不做任何转换，写什么就是什么。
  static Future<void> raw(String content) => _write(content, '已复制原文');

  /// 复制去标记后的纯文本，便于粘进文档 / 其他聊天软件。
  static Future<void> plain(String content) =>
      _write(ChatMarkdown.strip(content), '已复制纯文本');

  /// 提示回调的测试替身。
  ///
  /// 真实路径走 `AppSnackbar`，它依赖 GetMaterialApp 的 overlay；widget 测试里
  /// 让 snackbar 真跑起来会留下 2 秒 duration + 1 秒动画的挂起定时器，
  /// 反而把断言搞脏。留这个 seam，测试就只需要关心「复制了什么」。
  @visibleForTesting
  static void Function(String label, String message)? debugToastOverride;

  static Future<void> _write(String text, String label) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _toast(label, _preview(text));
  }

  static void _toast(String label, String message) {
    final override = debugToastOverride;
    if (override != null) {
      override(label, message);
      return;
    }
    try {
      AppSnackbar.show(label, message, duration: const Duration(seconds: 2));
    } catch (e) {
      // 提示是次要效果：弹不出来也绝不能让复制本身失败。
      debugPrint('复制提示未显示: $e');
    }
  }

  /// 提示条里的单行预览：压平换行并截断。
  ///
  /// 不做这一步的话，一条带表格的长消息会把提示条撑成占半屏的一块。
  static String _preview(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 40 ? flat : '${flat.substring(0, 40)}…';
  }
}

/// 给聊天气泡挂上复制入口：长按（全平台）与右键（桌面端）弹菜单，
/// 桌面端悬停时在气泡右上角显示一个复制角标。
///
/// **必须包在气泡最外层**（`_bubble` 里包住 `bubble` 那个 Container），
/// 不要塞进 `ChatRichText` 内部：超 600 字的消息折叠态不挂载 `GptMarkdown`，
/// 入口放进去就够不着全文了。这也是「整条复制原文」相对「选区复制」的主要优势
/// ——折叠态照样能复制到完整内容。
class ChatCopyWrapper extends StatefulWidget {
  const ChatCopyWrapper({
    super.key,
    required this.content,
    required this.child,
    this.bubbleColor,
  });

  /// 服务端原样下发的消息正文（不是 prepare 后的文本）。
  final String content;

  /// 气泡本体。
  final Widget child;

  /// 气泡底色。悬停角标用它做背景，避免在两种气泡色上出现一块突兀的补丁。
  final Color? bubbleColor;

  @override
  State<ChatCopyWrapper> createState() => _ChatCopyWrapperState();
}

class _ChatCopyWrapperState extends State<ChatCopyWrapper> {
  static const String _actionRaw = 'copy_raw';
  static const String _actionPlain = 'copy_plain';

  bool _hovering = false;

  /// 悬停角标只在真有指针悬停概念的平台出现。
  /// 移动端 `onEnter` 永远不会触发，提前判平台可以少挂一层 MouseRegion。
  static bool get _hasPointer => switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => false,
        _ => true,
      };

  Future<void> _run(String? action) async {
    switch (action) {
      case _actionRaw:
        await ChatCopy.raw(widget.content);
      case _actionPlain:
        await ChatCopy.plain(widget.content);
    }
  }

  /// 桌面端右键菜单：贴着鼠标位置弹出。
  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        _menuItem(_actionRaw, Icons.content_copy_outlined, '复制原文'),
        _menuItem(_actionPlain, Icons.notes_outlined, '复制纯文本'),
      ],
    );
    await _run(action);
  }

  /// 移动端 / 长按：底部菜单。用 bottom sheet 而不是 showMenu，
  /// 手指按住的地方在气泡中部，菜单贴着触点弹会盖住内容本身。
  Future<void> _showActionSheet(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.content_copy_outlined),
              title: const Text('复制原文'),
              subtitle: const Text('保留 Markdown / LaTeX 标记'),
              onTap: () => Navigator.of(ctx).pop(_actionRaw),
            ),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('复制纯文本'),
              subtitle: const Text('去掉标记，便于粘贴'),
              onTap: () => Navigator.of(ctx).pop(_actionPlain),
            ),
          ],
        ),
      ),
    );
    await _run(action);
  }

  /// 上下文菜单项。
  ///
  /// 只放「图标 + 一行文字」，不加副标题：`showMenu` 的弹层有最大宽度限制
  /// （Material 的 `_kMenuMaxWidth`），副标题一长就会撑出
  /// `A RenderFlex overflowed ... on the right`。
  ///
  /// 另外这里只能用 Icon + Text，**不能放按钮**——按钮主题的 minimumSize
  /// 宽度是无穷大，放进 Row 会直接抛 "BoxConstraints forces an infinite width"。
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: AppDesign.spaceXS),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 悬停角标压在气泡右上角**内部**，不能放到气泡外面：
    // MouseRegion 的命中区等于 Stack 的尺寸，角标一旦越界，
    // 指针移上去就触发 onExit → 角标消失 → 永远点不到。
    final showChip = _hovering && _hasPointer;
    final stack = Stack(
      children: [
        widget.child,
        if (showChip)
          Positioned(
            top: 2,
            right: 2,
            child: _CopyChip(
              background: widget.bubbleColor,
              onTap: () => ChatCopy.raw(widget.content),
            ),
          ),
      ],
    );

    return GestureDetector(
      onLongPress: () => _showActionSheet(context),
      onSecondaryTapDown: (d) => _showContextMenu(context, d.globalPosition),
      child: _hasPointer
          ? MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: stack,
            )
          : stack,
    );
  }
}

/// 悬停时出现的复制角标。
class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.onTap, this.background});

  final VoidCallback onTap;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppTooltip(
      message: '复制原文',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background ?? scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant, width: 0.5),
            ),
            child: Icon(
              Icons.content_copy_outlined,
              size: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
