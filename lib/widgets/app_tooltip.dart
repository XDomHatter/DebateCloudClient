import 'dart:async';

import 'package:debate_cloud/app/app_design.dart';
import 'package:flutter/material.dart';

/// 悬停提示。
///
/// 刻意**不用** `package:flutter/material.dart` 的 `Tooltip`：它在 Windows
/// 上会触发引擎 Bug（flutter/flutter#182444，P2，3.41.6 仍未修）——
/// tooltip 的浮层节点是 `OverlayPortal` 的 `_RenderDeferredLayoutBox`，
/// 语义上通过 `traversalChildIdentifier` "嫁接" 到 tooltip 的 child 上；
/// 在两个相邻 tooltip 之间悬停切换时，旧节点先被 detach 过滤、traversal
/// parent 收不到通知，AXTree 仍以为它挂着那个已销毁的节点，于是刷
/// `Failed to update ui::AXTree, error: N will not be in the tree...`。
///
/// 这里改成自己往 `Overlay` 里插一个普通的 `OverlayEntry`：没有 deferred
/// layout box，也就没有被嫁接的语义节点，移除时走的是常规删除路径。
/// 无障碍名称改由 `SemanticsProperties.tooltip` 提供，屏幕阅读器不受影响。
///
/// 目标下方至少要剩这么多高度，气泡才放下面；否则翻到上方。
const double _flipThreshold = 64;

/// 只做桌面端鼠标悬停：移动端没有 hover，也就不显示。
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 400),
    this.verticalOffset = 8,
  });

  final String message;
  final Widget child;

  /// 鼠标停多久才显示。给一点延迟，免得划过一排图标时连闪。
  final Duration waitDuration;

  /// 气泡与目标上边缘的间距。
  final double verticalOffset;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _timer;

  /// 气泡放目标下方（`true`）还是上方（`false`）。显示前按目标在屏幕上的
  /// 剩余空间算一次，免得贴边的按钮把气泡顶到屏幕外。
  bool _placeBelow = true;

  @override
  void dispose() {
    _cancel();
    _remove();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  void _scheduleShow() {
    _cancel();
    if (widget.message.isEmpty) return;
    _timer = Timer(widget.waitDuration, _show);
  }

  void _hide() {
    _cancel();
    _remove();
  }

  void _show() {
    _timer = null;
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    // 没有 Overlay 祖先（例如裸 widget 测试）就静默降级为不显示。
    if (overlay == null) return;
    _placeBelow = _computePlaceBelow();
    _entry = OverlayEntry(builder: _buildBubble);
    overlay.insert(_entry!);
  }

  /// 目标下方剩余高度够放气泡就放下面，否则翻到上面。
  ///
  /// 阈值取「气泡典型高度 + 间距」的粗略值：宁可早一点翻，也不要被裁掉。
  bool _computePlaceBelow() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    final viewSize = MediaQuery.maybeSizeOf(context);
    if (viewSize == null) return true;
    final top = box.localToGlobal(Offset.zero).dy;
    return viewSize.height - (top + box.size.height) >= _flipThreshold;
  }

  Widget _buildBubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final below = _placeBelow;
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
      followerAnchor: below ? Alignment.topCenter : Alignment.bottomCenter,
      offset: Offset(0, below ? widget.verticalOffset : -widget.verticalOffset),
      child: IgnorePointer(
        // Align 是必需的，不是装饰：Overlay 给 entry 的是**整屏紧约束**，
        // follower 会 `size = constraints.biggest` 并把它原样透传给 child，
        // 于是 ConstrainedBox(maxWidth) 被 BoxConstraints.enforce 反向
        // clamp 成整屏宽 —— 气泡会被撑成一个盖住半屏的实心大块。
        // Align 会把约束 loosen 回 0..整屏，气泡才能按内容收缩；
        // 同时它的 alignment 必须和 followerAnchor 一致（气泡的那个角
        // 才会落在锚点上）。
        child: Align(
          alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(AppDesign.radiusS),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesign.spaceS,
                    vertical: AppDesign.spaceXS,
                  ),
                  child: Text(
                    widget.message,
                    style: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      tooltip: widget.message,
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _scheduleShow(),
          onExit: (_) => _hide(),
          child: widget.child,
        ),
      ),
    );
  }
}
