import 'package:debate_cloud/app/app_design.dart';
import 'package:flutter/material.dart';

/// 屏幕档位。
enum AppScreenSize {
  /// 手机：< 600
  compact,

  /// 平板 / 小窗口：600 – 1023
  medium,

  /// 桌面：>= 1024
  expanded,
}

/// 断点判定与响应式布局工具。
abstract final class AppScreen {
  static AppScreenSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= AppDesign.bpExpanded) return AppScreenSize.expanded;
    if (width >= AppDesign.bpMedium) return AppScreenSize.medium;
    return AppScreenSize.compact;
  }
}

extension AppScreenX on BuildContext {
  AppScreenSize get screenSize => AppScreen.of(this);

  bool get isCompact => screenSize == AppScreenSize.compact;

  bool get isExpanded => screenSize == AppScreenSize.expanded;

  bool get isNotCompact => screenSize != AppScreenSize.compact;
}

/// 按屏幕档位选择不同的界面结构。
///
/// [medium] 未给出时回退到 [compact]。
class ResponsiveLayout extends StatelessWidget {
  final Widget compact;
  final Widget? medium;
  final Widget expanded;

  const ResponsiveLayout({
    super.key,
    required this.compact,
    this.medium,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return switch (AppScreen.of(context)) {
      AppScreenSize.expanded => expanded,
      AppScreenSize.medium => medium ?? compact,
      AppScreenSize.compact => compact,
    };
  }
}

/// 桌面端把内容限制在最大宽度内并居中，移动端则铺满。
class AppContentWidth extends StatelessWidget {
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const AppContentWidth({
    super.key,
    this.maxWidth = AppDesign.maxContentWidth,
    this.padding = const EdgeInsets.all(AppDesign.spaceM),
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 自适应列数的网格。
///
/// 列数 = 可用宽度 / ([minItemWidth] + 间距)，并限制在 1 – [maxColumns] 之间。
class AppResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  const AppResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = AppDesign.minCardWidth,
    this.maxColumns = 3,
    this.spacing = AppDesign.spaceS,
    this.runSpacing = AppDesign.spaceS,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final raw = (width + spacing) / (minItemWidth + spacing);
        final columns = raw.floor().clamp(1, maxColumns);
        final itemWidth = (width - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// 桌面端左右双栏，移动端上下堆叠。
class ResponsiveColumns extends StatelessWidget {
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;

  const ResponsiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 1,
    this.rightFlex = 2,
    this.spacing = AppDesign.spaceL,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, SizedBox(height: spacing), right],
      );
    }
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(flex: leftFlex, child: left),
        SizedBox(width: spacing),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }
}
