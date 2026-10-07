import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:flutter/material.dart';

/// 统一的卡片。
///
/// 移动端为铺满宽度的圆角描边卡片；桌面端在可点击时提供 hover 反馈。
class AppCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? accentColor;
  final double width;

  /// 选中态（master-detail 里被选中的列表项）。
  ///
  /// 只用描边 + 底色来表达：再加阴影会与 hover 态打架，看着像「悬停卡住了」。
  final bool selected;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppDesign.spaceM),
    this.accentColor,
    this.width = double.infinity,
    this.selected = false,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = context.appBorderColor;
    final clickable = widget.onTap != null;
    final hovering = _hovering && clickable;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedScale(
          // 按下时轻微回弹，给桌面端点击一个明确的即时反馈。
          scale: _pressed ? 0.985 : 1,
          duration: AppDesign.fast,
          child: AnimatedContainer(
            duration: AppDesign.fast,
            // hardEdge 足以裁掉贴边色条等溢出内容：antiAlias 的抗锯齿
            // 裁剪在移动浏览器上是每卡片一次的额外光栅开销。
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: widget.selected
                  ? scheme.primaryContainer.withValues(alpha: 0.45)
                  : context.appCardColor,
              borderRadius: BorderRadius.circular(AppDesign.radiusL),
              border: Border.all(
                color: widget.selected
                    ? scheme.primary
                    : hovering
                    ? scheme.primary.withValues(alpha: 0.5)
                    : border,
              ),
              boxShadow: hovering
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: clickable
                  ? InkWell(
                      onTap: widget.onTap,
                      onTapDown: (_) => setState(() => _pressed = true),
                      onTapUp: (_) => setState(() => _pressed = false),
                      onTapCancel: () => setState(() => _pressed = false),
                      child: _content(),
                    )
                  : _content(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return Stack(
      children: [
        if (widget.accentColor != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 4, color: widget.accentColor),
          ),
        Padding(
          padding: widget.accentColor == null
              ? widget.padding
              : widget.padding.add(const EdgeInsets.only(left: AppDesign.spaceXXS)),
          child: widget.child,
        ),
      ],
    );
  }
}

/// 状态药丸：颜色随明暗主题与语义槽位自动切换。
class AppStatusChip extends StatelessWidget {
  final String label;
  final AppStatus status;
  final IconData? icon;

  const AppStatusChip({super.key, required this.label, required this.status, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = context.statusStyleOf(status);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppDesign.radiusS),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: style.foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: text.labelMedium?.copyWith(color: style.foreground),
          ),
        ],
      ),
    );
  }
}

/// 分组容器：把一组字段 / 列表项收拢在一个低层表面上。
///
/// 视觉层级里的一级「块」——比 [AppCard] 更弱（无描边、底色更浅），
/// 用来承载本身就带分隔线的列表（如资料页的签名 / 注册时间 / 最近更新），
/// 避免「卡片里再套卡片」把页面切成一堆碎片。
class AppPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AppPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: AppDesign.spaceXS),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppDesign.radiusL),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 骨架屏的基础块。
///
/// 首屏加载用它替代全屏转圈：版式先成型，避免内容到达时整页跳动。
/// 只有首屏（列表为空）才用；下拉刷新时保持旧列表可见。
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  /// 关闭呼吸动画（测试里留着 AnimationController 会挂住定时器）。
  static bool animate = true;

  const AppSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppDesign.radiusS,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!AppSkeleton.animate) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    final controller = _controller;
    if (controller == null) return base;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(controller),
      child: base,
    );
  }
}

/// 一排骨架列表项：头像块 + 两行文字块，用于会话 / 好友 / 赛事列表首屏。
class AppSkeletonList extends StatelessWidget {
  final int itemCount;
  final bool showAvatar;

  const AppSkeletonList({super.key, this.itemCount = 5, this.showAvatar = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < itemCount; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
            child: AppSkeleton(
              height: showAvatar ? 68 : 88,
              radius: AppDesign.radiusL,
            ),
          ),
      ],
    );
  }
}

/// 聊天窗口首屏骨架：左右交替的气泡占位，版式与真实消息流一致。
class AppSkeletonChat extends StatelessWidget {
  final int itemCount;

  const AppSkeletonChat({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            vertical: AppDesign.spaceM,
            horizontal: AppDesign.spaceM,
          ),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            final isMe = i.isOdd;
            final bubbleWidth = (maxWidth * (isMe ? 0.52 : 0.64)).clamp(
              120.0,
              420.0,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
              child: Row(
                mainAxisAlignment: isMe
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  AppSkeleton(
                    width: bubbleWidth,
                    height: isMe ? 40 : 58,
                    radius: AppDesign.radiusL,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 列表 / 网格里最常见的「摘要卡片」：标题行 + 可选描述 + 状态 + 元信息 + 页脚。
///
/// 赛事卡片先后在赛事中心、赛事审批、我的赛事、赛事详情四处各写了一遍，
/// 字号与间距已经开始分叉（titleMedium 漂到 titleSmall）。这里收成一处，
/// 各处只传数据，不再各自拼 Column。
///
/// [large] 用于网格里的大卡片（标题放大、描述留 2 行），紧凑列表用默认值。
/// [leading] 是放在标题行左侧的小图标块；整块横向铺开的条目（如会话行）
/// 不属于这个形态，请直接用 [AppCard]。
class AppInfoCard extends StatelessWidget {
  final String title;
  final String? description;
  final AppStatus? status;
  final String? statusLabel;
  final List<AppMetaRow>? meta;
  final List<Widget>? chips;
  final Widget? footer;
  final Widget? leading;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool large;

  /// 选中态，双栏布局里被选中的列表项。
  final bool selected;

  const AppInfoCard({
    super.key,
    required this.title,
    this.description,
    this.status,
    this.statusLabel,
    this.meta,
    this.chips,
    this.footer,
    this.leading,
    this.onTap,
    this.accentColor,
    this.large = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasDescription = description != null && description!.isNotEmpty;
    final hasChips = chips != null && chips!.isNotEmpty;
    final hasMeta = meta != null && meta!.isNotEmpty;

    return AppCard(
      accentColor: accentColor,
      onTap: onTap,
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AppDesign.spaceS),
              ],
              Expanded(
                // 固定高度的网格（赛事中心 mainAxisExtent 168）容不下两行标题，
                // 统一单行省略；需要完整标题时请走详情页。
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (large ? text.titleMedium : text.titleSmall)?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (status != null && statusLabel != null) ...[
                const SizedBox(width: AppDesign.spaceXS),
                AppStatusChip(label: statusLabel!, status: status!),
              ],
            ],
          ),
          if (hasDescription) ...[
            SizedBox(height: large ? AppDesign.spaceXS : AppDesign.spaceXXS),
            Text(
              description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (hasChips) ...[
            const SizedBox(height: AppDesign.spaceS),
            Wrap(
              spacing: AppDesign.spaceXS,
              runSpacing: AppDesign.spaceXS,
              children: chips!,
            ),
          ],
          if (hasMeta) ...[
            const SizedBox(height: AppDesign.spaceS),
            ...meta!,
          ],
          if (footer != null) ...[
            const SizedBox(height: AppDesign.spaceM),
            footer!,
          ],
        ],
      ),
    );
  }
}

/// 区块标题。
class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final IconData? icon;

  const AppSectionHeader({super.key, required this.title, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: AppDesign.spaceXS),
        ],
        Expanded(
          child: Text(
            title,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 图标 + 说明的元信息行。
class AppMetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const AppMetaRow({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spaceXXS),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppDesign.spaceXS),
          Text(
            label,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: AppDesign.spaceS),
          Expanded(
            child: Text(
              value,
              style: text.bodySmall?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区内的轻量空态（一行说明文字）。
class AppSectionEmpty extends StatelessWidget {
  final String message;

  const AppSectionEmpty(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceS),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// 统一的空态 / 错误态占位。
///
/// 文案分两级：[title] 是结论（如「暂无赛事」），[message] 是解释或补救
/// 说明，[hint] 是可省略的补充。只有 [message] 时它就是唯一正文（保持旧
/// 调用点的观感）。三态（无数据 / 无搜索结果 / 网络错误）靠图标与文案区分，
/// 不再靠同一个占位符硬套。
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double verticalPadding;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
    this.verticalPadding = AppDesign.spaceXXL,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: verticalPadding,
        horizontal: AppDesign.spaceL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 外圈 + 内底双层：单色圆块在浅色模式下太"贴"，加一圈描边后
          // 视觉重量与卡片接近，空态不显得塌陷。
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.22),
                width: 1.5,
              ),
            ),
            child: Icon(icon, size: 32, color: scheme.primary),
          ),
          const SizedBox(height: AppDesign.spaceM),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: AppDesign.spaceXS),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: (title == null ? text.bodyMedium : text.bodySmall)?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppDesign.spaceXXS),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDesign.spaceL),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// 统一的加载态。
class AppLoading extends StatelessWidget {
  final String? message;

  const AppLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: scheme.primary),
          if (message != null) ...[
            const SizedBox(height: AppDesign.spaceM),
            Text(
              message!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面端必须限制弹窗宽度，否则输入框会被无限拉宽。
class AppDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppDesign.maxDialogWidth),
      child: AlertDialog(
        title: Text(title, style: text.titleMedium?.copyWith(color: scheme.onSurface)),
        content: content,
        actions: actions,
      ),
    );
  }
}
