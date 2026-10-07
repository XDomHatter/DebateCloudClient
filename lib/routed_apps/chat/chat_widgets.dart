import 'dart:async';

import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/local_media.dart';
import 'package:debate_cloud/app/video_poster.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// 视频初始化超时。
///
/// 平台实现缺失或原生解码卡死时，宁可给出明确的失败态，也不要无限转圈。
const Duration _videoInitTimeout = Duration(seconds: 15);

/// 释放播放器时的超时兜底。
const Duration _videoDisposeTimeout = Duration(seconds: 3);

/// 安全释放播放器控制器（带超时）。
///
/// 必须带超时兜底：`VideoPlayerController.dispose()` 内部第一件事是
/// `await _creatingCompleter!.future`，而该 Completer 只在 `initialize()`
/// 走到 `complete()` 时才完成。若 `create()` 抛异常（例如 Windows 上
/// video_player 没有平台实现，占位实现会同步抛 UnimplementedError），
/// 它既不 `complete` 也不 `completeError`，`dispose()` 便会**永久挂起**。
/// 把 dispose 放在错误处理路径上时，一旦 await 它，后面的状态切换就再也
/// 执行不到，界面会永远停在加载动画上。
Future<void> _safeDisposeVideo(VideoPlayerController c) async {
  try {
    await c.dispose().timeout(_videoDisposeTimeout);
  } catch (_) {
    // 初始化失败 / 已释放 / 超时：都无需再处理。
  }
}

/// 聊天模块共享头像：优先展示服务器头像，无头像时用首字符占位，
/// 可选在线状态圆点。
///
/// 占位底色由 [userId] 推导，同一用户在任何页面颜色保持一致。
/// [onTap] 非空时头像可点击（如进入个人主页），由调用点决定行为。
class ChatAvatar extends StatefulWidget {
  final int userId;
  final String name;
  final bool hasAvatar;

  /// 头像版本（好友/搜索/申请接口下发），变化时自动重新下载。
  final String? avatarUpdatedAt;
  final double radius;
  final bool? online;
  final VoidCallback? onTap;

  const ChatAvatar({
    super.key,
    required this.userId,
    required this.name,
    this.hasAvatar = false,
    this.avatarUpdatedAt,
    this.radius = 22,
    this.online,
    this.onTap,
  });

  @override
  State<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<ChatAvatar> {
  CachedMedia? _media;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表项复用时 userId 会变化，必须重新拉取，否则会串头像；
    // 头像版本变化说明对方更新了头像，同样需要重拉。
    if (oldWidget.userId != widget.userId ||
        oldWidget.hasAvatar != widget.hasAvatar ||
        oldWidget.avatarUpdatedAt != widget.avatarUpdatedAt) {
      _media = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.hasAvatar) return;
    final requestedId = widget.userId;
    try {
      final auth = Get.find<AuthService>();
      final media = await ChatSDK.fetchUserAvatar(
        auth.userObj.value,
        requestedId,
        version: widget.avatarUpdatedAt,
      );
      // 请求返回期间 widget 可能已被复用给另一个用户。
      if (!mounted || media == null || requestedId != widget.userId) return;
      setState(() => _media = media);
    } catch (_) {
      // 头像加载失败时保留首字符占位图，不影响列表可用性。
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.name.trim().isEmpty ? '?' : widget.name.trim();
    final size = widget.radius * 2;
    // 头像只显示在 size×size 的圆里，按物理像素尺寸解码，避免把原图
    // 整幅位图搬进显存——移动浏览器上这是滚动卡顿与内存的大头。
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final decodeWidth = (size * dpr).round().clamp(48, 192);
    final avatarImage = _media == null
        ? null
        : ResizeImage(_media!.imageProvider(), width: decodeWidth);
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _seedColor(widget.userId),
        shape: BoxShape.circle,
        image: avatarImage != null
            ? DecorationImage(image: avatarImage, fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: avatarImage == null
          ? Text(
              name.characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: widget.radius * 0.85,
                height: 1.1,
                color: AppPalette.white,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
    if (widget.online == null) return _tappable(avatar);
    return _tappable(
      SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: widget.radius * 0.55,
                height: widget.radius * 0.55,
                decoration: BoxDecoration(
                  // 走语义槽位而非硬编码绿：深色模式下用提亮版，保证小圆点仍可辨。
                  color: widget.online!
                      ? context.statusStyleOf(AppStatus.success).foreground
                      : scheme.outlineVariant,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.appCardColor, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// onTap 非空时整体可点击；桌面端同时给出手型光标。
  Widget _tappable(Widget child) {
    if (widget.onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onTap, child: child),
    );
  }

  /// 由用户 id 推导稳定底色，避免所有占位头像同色难以区分。
  static Color _seedColor(int userId) {
    final hue = (userId <= 0 ? 180 : (userId * 47) % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.38, 0.46).toColor();
  }
}

/// 未读计数徽标。计数为 0 时自动不占位。
class ChatBadge extends StatelessWidget {
  final int count;

  const ChatBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // 用 error / onError 而非固定红：与 Material 的 Badge 默认配色一致，
        // 且跟随主题明暗自动调整。
        color: scheme.error,
        borderRadius: BorderRadius.circular(AppDesign.radiusFull),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: text.labelSmall?.copyWith(
          color: scheme.onError,
          height: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 内联小按钮。
///
/// 全站按钮主题把最小高度设为 48，直接用在列表行里会把行撑得很高，
/// 这里统一压制为 34 的紧凑尺寸。
enum ChatButtonVariant { filled, tonal, outlined }

class ChatSmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ChatButtonVariant variant;
  final IconData? icon;
  final Color? foreground;

  const ChatSmallButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ChatButtonVariant.filled,
    this.icon,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(const Size(0, 34)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: AppDesign.spaceS),
      ),
      textStyle: WidgetStateProperty.all(text.labelMedium),
      foregroundColor:
          foreground == null ? null : WidgetStateProperty.all(foreground),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15),
              const SizedBox(width: AppDesign.spaceXXS),
              Text(label),
            ],
          );
    return switch (variant) {
      ChatButtonVariant.filled => FilledButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
      ChatButtonVariant.tonal => FilledButton.tonal(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
      ChatButtonVariant.outlined => OutlinedButton(
          onPressed: onPressed,
          style: style,
          child: child,
        ),
    };
  }
}

/// 在线 / 离线状态点 + 文字，用于好友行副标题。
class ChatPresenceLine extends StatelessWidget {
  final bool online;
  final String? trailingText;

  const ChatPresenceLine({super.key, required this.online, this.trailingText});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final color = online
        ? context.statusStyleOf(AppStatus.success).foreground
        : scheme.onSurfaceVariant;
    final preview = trailingText?.trim() ?? '';
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          online ? '在线' : '离线',
          style: text.labelSmall?.copyWith(color: color),
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(width: AppDesign.spaceXXS),
          Text(
            '·',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppDesign.spaceXXS),
          Expanded(
            child: Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

/// 用户名 / 时间等辅助信息行。
class ChatSubLine extends StatelessWidget {
  final String text;
  final int maxLines;

  const ChatSubLine(this.text, {super.key, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// 时间格式化。服务器时间为 UTC（SQLite CURRENT_TIMESTAMP），统一转本地展示。
abstract final class ChatTimeFmt {
  static DateTime? _parse(String s) {
    if (s.isEmpty) return null;
    final iso = s.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(iso.endsWith('Z') ? iso : '${iso}Z')?.toLocal();
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 列表/会话摘要用：今天只显示时间，昨天带"昨天"，更早只带日期。
  static String shortTime(String s) {
    final d = _parse(s);
    if (d == null) return '';
    final now = DateTime.now();
    final dayDiff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (dayDiff == 0) return _hm(d);
    if (dayDiff == 1) return '昨天 ${_hm(d)}';
    if (now.year == d.year) return '${d.month}月${d.day}日';
    return '${d.year}/${d.month}/${d.day}';
  }

  /// 气泡内用：始终 HH:mm。
  static String bubbleTime(String s) {
    final d = _parse(s);
    return d == null ? '' : _hm(d);
  }

  /// 消息流日期分隔符：今天 / 昨天 / M月d日 / yyyy年M月d日。
  static String dateLabel(String s) {
    final d = _parse(s);
    if (d == null) return '';
    final now = DateTime.now();
    final dayDiff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (dayDiff == 0) return '今天';
    if (dayDiff == 1) return '昨天';
    if (now.year == d.year) return '${d.month}月${d.day}日';
    return '${d.year}年${d.month}月${d.day}日';
  }

  /// 日期分组键（仅日期部分），用于判断相邻消息是否同一天。
  static String dateKey(String s) {
    final d = _parse(s);
    if (d == null) return s;
    return '${d.year}-${d.month}-${d.day}';
  }
}

/// 群聊头像：圆形底 + 群组图标，底色由 [groupId] 推导，同一群颜色稳定。
class GroupAvatar extends StatelessWidget {
  final int groupId;
  final double radius;

  const GroupAvatar({super.key, required this.groupId, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final hue = (groupId <= 0 ? 210 : (groupId * 47 + 210) % 360).toDouble();
    final size = radius * 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(1, hue, 0.38, 0.46).toColor(),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.group_rounded,
        size: radius * 1.1,
        color: AppPalette.white,
      ),
    );
  }
}

/// 群主身份小徽标。
class OwnerChip extends StatelessWidget {
  const OwnerChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppDesign.radiusFull),
      ),
      child: Text(
        '群主',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 好友多选列表：创建群聊 / 拉人入群共用。
/// 列表内容原样渲染，筛选（如排除已在群成员）由调用方负责；
/// [selected] 为响应式列表，勾选状态自动随其变化。
class FriendCheckList extends StatelessWidget {
  final List<Friend> friends;
  final RxList<int> selected;
  final ValueChanged<int> onToggle;

  const FriendCheckList({
    super.key,
    required this.friends,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (friends.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceL),
        child: Center(
          child: Text(
            '没有可选择的好友',
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final f in friends)
          InkWell(
            onTap: () => onToggle(f.userId),
            borderRadius: BorderRadius.circular(AppDesign.radiusM),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  ChatAvatar(
                    userId: f.userId,
                    name: f.displayName,
                    hasAvatar: f.hasAvatar,
                    avatarUpdatedAt: f.avatarUpdatedAt,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      f.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Obx(() {
                    return Checkbox(
                      value: selected.contains(f.userId),
                      onChanged: (_) => onToggle(f.userId),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 聊天输入区的 TapRegion 分组 id。
///
/// 桌面端（Windows / Linux / macOS）点击输入框之外会命中 Flutter 的默认行为
/// `_EditableTextTapOutsideAction`，它无条件调用 `focusNode.unfocus()`
/// （见 `widgets/editable_text.dart`）。于是点「发送」按钮或 Markdown 工具条
/// 都会被判定为「输入框外点击」而丢掉焦点，必须重新点一次输入框。
///
/// 把输入区自有控件用同一个 [groupId] 包进 [TextFieldTapRegion]，
/// 它们就与输入框视为同一区域，点击不再失焦；点击消息列表、AppBar 等
/// 真正的输入区外区域仍会正常失焦。
const Object chatInputTapGroupId = _ChatInputTapGroupId();

/// [chatInputTapGroupId] 的载体，仅用于提供一个稳定的常量对象身份。
class _ChatInputTapGroupId {
  const _ChatInputTapGroupId();
}

/// 聊天输入区：Markdown 快捷插入条 + 输入框。
///
/// 换行策略——Markdown 必须有换行能力，否则列表、代码块、块级公式都写不出来：
/// - 桌面端：Enter 发送，Shift/Ctrl+Enter 换行（保持原有的 Enter 发送习惯）；
/// - 移动端：Enter 换行，发送交给右侧按钮。
///
/// 焦点策略——发送后焦点必须留在输入框：
/// - `onEditingComplete` 传空回调，阻止 `EditableText` 在 send 动作后
///   主动 `focusNode.unfocus()`（`_finalizeEditing` 只在 `onEditingComplete`
///   为 null 时才走失焦分支）；
/// - 输入框与发送按钮、工具条共用 [chatInputTapGroupId]，避免点按钮失焦。
///
/// 调用方若把发送按钮放在本组件之外（如页面底部的 `_inputBar`），
/// 需要用 `TextFieldTapRegion(groupId: chatInputTapGroupId, ...)` 包住它。
class ChatInputField extends StatelessWidget {
  const ChatInputField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.focusNode,
    this.hintText = '输入消息…',
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  /// 由页面持有，便于在发送后恢复焦点。
  final FocusNode? focusNode;
  final String hintText;
  final bool enabled;
  final bool autofocus;

  static bool get _isMobile => switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  /// 当前平台是否移动端。页面据此决定要不要自动聚焦输入框
  /// （移动端自动聚焦会直接弹出软键盘，通常不是期望行为）。
  static bool get isMobilePlatform => _isMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context),
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter &&
                (HardwareKeyboard.instance.isShiftPressed ||
                    HardwareKeyboard.instance.isControlPressed)) {
              _replaceSelection('\n', caretAfter: 1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: autofocus,
            // 与发送按钮、工具条同组：点击它们不算「输入框外点击」。
            groupId: chatInputTapGroupId,
            // 非空回调会阻止 EditableText 在 send 动作后 focusNode.unfocus()。
            onEditingComplete: () {},
            minLines: 1,
            maxLines: 6,
            textInputAction:
                _isMobile ? TextInputAction.newline : TextInputAction.send,
            onSubmitted: _isMobile ? null : (_) => onSubmitted(),
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  /// 五个工具按钮的固定总宽（每个 [SizedBox] 32）。
  static const double _toolbarButtonsWidth = 32 * 5;

  /// 给提示文字预留的宽度（不含按钮），按平台文案长短区分。
  ///
  /// 这是**估宽**而非精算：文字宽度拿不到布局前的值，用 `TextPainter` 测量
  /// 又要把字号 / 字重 / 字体族都搬一遍，成本高且容易与实渲染脱节。这里取
  /// 略大于实测的估值，宁可早点隐藏，也不要放出一截被截断的提示。
  static const double _hintReserve = 96;
  static const double _hintReserveMobile = 136;

  Widget _toolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hint = _isMobile ? '支持 Markdown / LaTeX' : 'Shift+Enter 换行';

    // 工具条属于输入区的一部分：包进同组 TapRegion，点它不丢焦点，
    // 否则桌面端每次插入 Markdown 标记后光标都会掉出输入框。
    return TextFieldTapRegion(
      groupId: chatInputTapGroupId,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 按钮是固定宽度，让不了位；`Spacer` 又能被压成 0，所以宽度不够时
          // 唯一可牺牲的就是末尾那条提示文字——留半截「Shift+Enter 换…」
          // 既没信息量又难看，不如整条隐藏。
          //
          // 预留宽度按系统字号缩放同步放大：main.dart 把倍率钳在
          // [AppDesign.minTextScale, maxTextScale]，最大 1.3 倍。
          final scale = MediaQuery.textScalerOf(context)
              .scale(1.0)
              .clamp(AppDesign.minTextScale, AppDesign.maxTextScale)
              .toDouble();
          final reserve =
              (_isMobile ? _hintReserveMobile : _hintReserve) * scale;
          final showHint = constraints.maxWidth >= _toolbarButtonsWidth + reserve;

          return Row(
            children: [
              _toolButton(Icons.format_bold, '加粗', () => _wrap('**', '**')),
              _toolButton(Icons.format_italic, '斜体', () => _wrap('*', '*')),
              _toolButton(Icons.code, '行内代码', () => _wrap('`', '`')),
              _toolButton(Icons.functions, '公式', () => _wrap(r'$', r'$')),
              _toolButton(Icons.data_object, '代码块', () => _wrap('```\n', '\n```')),
              const Spacer(),
              if (showHint)
                Text(
                  hint,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return AppTooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          icon: Icon(icon, size: 17),
          iconSize: 17,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        ),
      ),
    );
  }

  /// 用 [left]/[right] 包裹当前选区，无选区时插入一对并把光标放在中间。
  void _wrap(String left, String right) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final selected = start <= end ? text.substring(start, end) : '';
    final next = text.replaceRange(start, end, '$left$selected$right');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + left.length + selected.length,
      ),
    );
  }

  /// 用 [value] 替换当前选区（Shift+Enter 换行走这里）。
  void _replaceSelection(String value, {required int caretAfter}) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + caretAfter),
    );
  }
}

/// 单条消息的列表项容器：消息对象未变化时直接复用上一次构建的子树。
///
/// reverse 消息列表每来一条新消息，ListView 会重建所有可见项；气泡里
/// 的 GptMarkdown 解析与排版开销大，按消息对象同一性跳过未变化项，
/// 让重排范围只落在真正新增/变化的那条上。调用方应以
/// `ValueKey('msg-<id>')` 作 key，元素按 key 复用后本守卫才能生效。
class ChatMessageTile extends StatefulWidget {
  const ChatMessageTile({
    super.key,
    required this.message,
    required this.showDate,
    required this.builder,
  });

  final ChatMessage message;

  /// 是否显示日期分隔：分隔线取决于相邻消息，变化时必须重建。
  final bool showDate;

  final WidgetBuilder builder;

  @override
  State<ChatMessageTile> createState() => _ChatMessageTileState();
}

class _ChatMessageTileState extends State<ChatMessageTile> {
  Widget? _cached;

  @override
  void didUpdateWidget(covariant ChatMessageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 发送去重等场景会用新对象替换同一 id 的旧消息，必须重建。
    if (!identical(widget.message, oldWidget.message) ||
        widget.showDate != oldWidget.showDate) {
      _cached = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 气泡宽度（MediaQuery）与配色（Theme）在 builder 里经本节点读取，
    // 环境变化（旋转 / 明暗切换）时一律弃用缓存。
    _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    return _cached ??= widget.builder(context);
  }
}

/// 媒体消息（图片 / 视频）的气泡内容。
///
/// 服务端只下发 mediaKey，字节需经信封鉴权下载到本地后才能渲染
/// （`Image.network` 带不了信封，见 `ChatSDK.fetchChatMedia`）。
/// 下载期间按 payload 里的宽高占位，图片就绪后列表不会发生跳动。
class ChatMediaBubble extends StatefulWidget {
  const ChatMediaBubble({
    super.key,
    required this.message,
    required this.maxWidth,
  });

  final ChatMessage message;

  /// 气泡可用最大宽度（由调用方按屏宽比例算出）。
  final double maxWidth;

  /// 媒体区最大高度：竖图不设上限会把整屏顶掉，滚动位置随之乱跳。
  static const double maxHeight = 320;

  @override
  State<ChatMediaBubble> createState() => _ChatMediaBubbleState();
}

class _ChatMediaBubbleState extends State<ChatMediaBubble> {
  CachedMedia? _media;
  bool _failed = false;

  String get _mediaKey => (widget.message.payload['key'] ?? '') as String;

  bool get _isVideo => widget.message.type == 'video';

  /// 宽高比取自 payload；缺失时按 4:3 兜底。
  double get _aspectRatio {
    final w = (widget.message.payload['width'] as num?)?.toDouble() ?? 0;
    final h = (widget.message.payload['height'] as num?)?.toDouble() ?? 0;
    if (w <= 0 || h <= 0) return 4 / 3;
    return (w / h).clamp(0.5, 2.0);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ChatMediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表项复用：mediaKey 变化时必须重新下载，否则会串图。
    if ((oldWidget.message.payload['key'] ?? '') != _mediaKey) {
      _media = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_mediaKey.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      final auth = Get.find<AuthService>();
      final m = await ChatSDK.fetchChatMedia(auth.userObj.value, _mediaKey);
      if (!mounted) return;
      setState(() {
        _media = m;
        _failed = m == null;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.maxWidth;
    final height = (width / _aspectRatio).clamp(120.0, ChatMediaBubble.maxHeight);

    Widget child;
    if (_failed) {
      child = _placeholder(
        context,
        Icons.broken_image_outlined,
        '媒体加载失败',
        width,
        height,
      );
    } else if (_media == null) {
      child = _placeholder(context, null, '', width, height, loading: true);
    } else if (_isVideo) {
      child = ChatVideoCover(media: _media!, width: width, height: height);
    } else {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => Get.to<void>(
            () => ChatMediaViewerPage(media: _media!, isVideo: false),
          ),
          child: Image(
            // 气泡只有几百逻辑像素宽，按物理像素解码即可；全尺寸位图
            // 在移动 GPU 上既慢解码又费显存。查看页仍用原图缩放。
            image: ResizeImage(
              _media!.imageProvider(),
              width: (width *
                      (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3))
                  .round()
                  .clamp(320, 1280),
            ),
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDesign.radiusM),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _placeholder(
    BuildContext context,
    IconData? icon,
    String text,
    double width,
    double height, {
    bool loading = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon ?? Icons.image_not_supported_outlined,
                  size: 26,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppDesign.spaceXXS),
                Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

/// 视频消息封面：优先展示首帧海报（静态图），点击进入全屏播放。
///
/// 列表里若为每个可见视频初始化完整播放器（Web 端即创建 <video> 并
/// 解码），移动端滚动开销巨大；因此先尝试用 video_poster 截一次首帧，
/// 成功则封面只是普通图片，失败（原生端 / 编码不支持 / 超时）才回退
/// 到播放器取首帧的原路径。
///
/// 列表里必须静音且不自动播放——滚动经过时突然出声非常打扰。
///
/// 播放器路径的初始化失败时（平台无实现、编码不支持、原生卡住）必须
/// 给出失败态：`VideoPlayerController.dispose()` 在 `initialize()` 抛
/// 异常后会永久挂起（见 [_safeDisposeVideo]），错误分支里若先 await 它，
/// 界面就再也切不到失败态，会永远停在加载动画上。
class ChatVideoCover extends StatefulWidget {
  const ChatVideoCover({
    super.key,
    required this.media,
    required this.width,
    required this.height,
  });

  final CachedMedia media;
  final double width;
  final double height;

  @override
  State<ChatVideoCover> createState() => _ChatVideoCoverState();
}

class _ChatVideoCoverState extends State<ChatVideoCover> {
  VideoPlayerController? _controller;
  ImageProvider? _poster;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 海报命中（或截帧成功）时封面只是一张图，绝不初始化播放器。
    final poster = await createVideoPoster(widget.media);
    if (!mounted) return;
    if (poster != null) {
      setState(() => _poster = poster);
      return;
    }
    final c = widget.media.createVideoController();
    try {
      await c.initialize().timeout(_videoInitTimeout);
      await c.setVolume(0);
      await c.seekTo(Duration.zero);
      if (!mounted) {
        unawaited(_safeDisposeVideo(c));
        return;
      }
      setState(() => _controller = c);
    } catch (e) {
      // 顺序很重要：**先**切到失败态，**再**释放控制器。
      // dispose 可能永久挂起（见 _safeDisposeVideo），颠倒顺序会让界面
      // 永远停在加载动画上——这正是之前 Windows 上的表现。
      debugPrint('视频封面初始化失败: $e');
      if (mounted) setState(() => _failed = true);
      unawaited(_safeDisposeVideo(c));
    }
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    // 不 await：State.dispose 是同步的，且 dispose 本身可能挂起。
    if (c != null) unawaited(_safeDisposeVideo(c));
    // blob URL 等媒体资源随之回收（原生实现为空操作）。
    widget.media.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _controller;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Get.to<void>(
          () => ChatMediaViewerPage(media: widget.media, isVideo: true),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null && c.value.isInitialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              )
            else if (_poster != null)
              Image(image: _poster!, fit: BoxFit.cover)
            else
              Container(
                color: scheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.videocam_off_outlined,
                            size: 26,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppDesign.spaceXXS),
                          Text(
                            '无法预览视频',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      )
                    : const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            // 半透明遮罩 + 播放图标：明确「这是可点的视频」。
            Container(color: AppPalette.black.withValues(alpha: 0.2)),
            Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppPalette.black.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppPalette.white,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 媒体全屏查看页：图片可缩放拖动，视频可播放 / 暂停。
class ChatMediaViewerPage extends StatefulWidget {
  const ChatMediaViewerPage({
    super.key,
    required this.media,
    required this.isVideo,
  });

  final CachedMedia media;
  final bool isVideo;

  @override
  State<ChatMediaViewerPage> createState() => _ChatMediaViewerPageState();
}

class _ChatMediaViewerPageState extends State<ChatMediaViewerPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final c = widget.media.createVideoController();
    try {
      await c.initialize().timeout(_videoInitTimeout);
      if (!mounted) {
        unawaited(_safeDisposeVideo(c));
        return;
      }
      setState(() => _controller = c);
      await c.play();
    } catch (e) {
      // 同 ChatVideoCover：先切失败态，再异步释放，避免 dispose 挂起卡住流程。
      debugPrint('视频播放页初始化失败: $e');
      if (mounted) setState(() => _failed = true);
      unawaited(_safeDisposeVideo(c));
    }
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    if (c != null) unawaited(_safeDisposeVideo(c));
    // blob URL 等媒体资源随之回收（原生实现为空操作）。
    widget.media.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppPalette.white,
        elevation: 0,
      ),
      body: Center(child: widget.isVideo ? _video() : _image()),
    );
  }

  Widget _image() => InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Image(image: widget.media.imageProvider(), fit: BoxFit.contain),
      );

  Widget _video() {
    if (_failed) {
      return const Text(
        '视频无法播放',
        style: TextStyle(color: AppPalette.white),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppPalette.white,
        ),
      );
    }
    // 播放状态变化要驱动重绘，必须订阅 controller 这个 ValueNotifier。
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, value, _) => GestureDetector(
        onTap: () => value.isPlaying ? c.pause() : c.play(),
        child: AspectRatio(
          aspectRatio: value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              // 暂停时才盖播放按钮，播放中不遮挡画面。
              if (!value.isPlaying)
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppPalette.black.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: AppPalette.white,
                    size: 34,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDesign.spaceS,
                    horizontal: AppDesign.spaceM,
                  ),
                  // 纯黑底上用 teal400（主色的提亮档）：teal500 在暗底上对比度不足。
                  colors: VideoProgressColors(
                    playedColor: AppPalette.teal400,
                    bufferedColor: AppPalette.white.withValues(alpha: 0.4),
                    backgroundColor: AppPalette.white.withValues(alpha: 0.2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 输入区附件按钮：选择图片 / 视频并交给调用方上传。
///
/// 必须与输入框同处 [chatInputTapGroupId] 分组，否则桌面端点它就会被判定为
/// 「输入框外点击」而丢掉焦点（见 [chatInputTapGroupId] 的说明）。
class ChatMediaPickerButton extends StatelessWidget {
  const ChatMediaPickerButton({
    super.key,
    required this.enabled,
    required this.onPicked,
    this.isUploading = false,
  });

  final bool enabled;
  final bool isUploading;

  /// 选好文件后回调；[isVideo] 区分类型，由调用方决定上传与发送方式。
  /// 回调传 [XFile]（cross_file，全平台可用）：原生端持有路径、Web 端
  /// 持有可读取的 blob，调用方无需依赖任何平台 API。
  final void Function(XFile file, bool isVideo) onPicked;

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      groupId: chatInputTapGroupId,
      child: AppTooltip(
        message: '发送图片或视频',
        child: IconButton.filledTonal(
          onPressed: enabled && !isUploading ? () => _pick(context) : null,
          icon: isUploading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('图片'),
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('视频'),
              onTap: () => Navigator.of(ctx).pop('video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final picker = ImagePicker();
    final XFile? file;
    if (choice == 'video') {
      file = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      // 先压缩再上传：原图动辄数 MB，聊天场景不需要全分辨率。
      file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    }
    if (file == null) return;
    onPicked(file, choice == 'video');
  }
}
