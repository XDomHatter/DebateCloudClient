import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/widgets/app_server_action.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';

/// 内容页统一骨架：AppBar + 居中限宽 + 下拉刷新 + 固定头部 + 加载态。
///
/// 此前十几个页面各写一遍
/// ```
/// Scaffold(
///   appBar: AppBar(title: ...),
///   body: RefreshIndicator(
///     onRefresh: ...,
///     child: ListView(
///       padding: const EdgeInsets.all(AppDesign.spaceM),
///       children: [Align(topCenter) → ConstrainedBox(maxContentWidth) → Column],
///     ),
///   ),
/// )
/// ```
/// 四件事被重复且各自分叉：限宽是否生效、刷新是否可用、加载态是否居中、
/// 固定头部要不要跟着滚。这里一次性收编，页面只负责给内容。
///
/// 用法：
/// - 内容是若干「块」→ 传 [children]，由脚手架包成可滚动的 ListView；
/// - 需要自定义滚动体（网格、无限列表）→ 传 [body]；
/// - 首屏加载 → 传 [loadingState]，整页居中显示，[children] / [body] 可省略。
///
/// 注意 [onRefresh] 非空时内容必须可滚动（[RefreshIndicator] 的硬性要求）；
/// [children] 天然满足，自传 [body] 时请自行保证。
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.appBar,
    this.showServerAction = true,
    this.onRefresh,
    this.header,
    this.maxWidth = AppDesign.maxContentWidth,
    this.padding = const EdgeInsets.all(AppDesign.spaceM),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.bottom,
    this.floatingActionButton,
    this.loadingState,
    this.body,
    this.children,
  }) : assert(
         body != null || children != null || loadingState != null,
         'body / children / loadingState 至少要给一个',
       );

  /// 标题；与 [appBar] 互斥，给了 [appBar] 就以它为准。
  final String? title;

  final List<Widget>? actions;
  final Widget? leading;

  /// 完全自定义的 AppBar（如标题是 Obx、需要 bottom 等）。
  final PreferredSizeWidget? appBar;

  /// 是否在 AppBar 上挂常驻的「服务器设置」入口。
  ///
  /// 默认开启：它是服务端下线时唯一还能改地址的退路（页面内容此时多半是
  /// 错误态，挂在内容里的入口会一起消失）。只有页面自己已提供入口、或
  /// AppBar 空间确实不够时才关掉。
  final bool showServerAction;

  /// 给了就包一层 [RefreshIndicator]，内容不足一屏也能拉出刷新。
  final Future<void> Function()? onRefresh;

  /// 内容区上方的固定区（搜索框、筛选条等），不随内容滚动，同样居中限宽。
  final Widget? header;

  /// 内容最大宽度：列表类用 [AppDesign.maxContentWidth]，阅读 / 表单类用
  /// [AppDesign.maxReadingWidth]。
  final double maxWidth;

  /// 内容内边距。
  ///
  /// 传 [children] 时它是 ListView 的 padding（滚动内容不会贴到边缘）；
  /// 传 [body] 时它是限宽盒子的 padding。
  final EdgeInsetsGeometry padding;

  /// 仅对 [children] 生效：内容块的横向对齐。
  final CrossAxisAlignment crossAxisAlignment;

  final Widget? bottom;
  final Widget? floatingActionButton;

  /// 首屏加载态。非空时整页显示它并居中，忽略 [body] / [children]。
  final Widget? loadingState;

  /// 现成的滚动体（ListView / CustomScrollView / SingleChildScrollView）。
  final Widget? body;

  /// 内容块；给了它就自动生成可滚动的 ListView。
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    final bar =
        appBar ??
        (title == null
            ? null
            : AppBar(
                title: Text(title!),
                leading: leading,
                actions: [
                  ...?actions,
                  // 放在最后：页面自己的操作优先，服务器是兜底退路。
                  if (showServerAction) const AppServerAction(),
                ],
              ));

    if (loadingState != null) {
      return Scaffold(
        appBar: bar,
        body: AppContentWidth(
          maxWidth: maxWidth,
          padding: padding,
          child: loadingState!,
        ),
        bottomNavigationBar: bottom,
        floatingActionButton: floatingActionButton,
      );
    }

    final scrollable = children != null
        ? ListView(
            // 内容不足一屏时也必须可拖动，否则下拉刷新失效。
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            children: [
              AppContentWidth(
                maxWidth: maxWidth,
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: crossAxisAlignment,
                  children: children!,
                ),
              ),
            ],
          )
        : AppContentWidth(maxWidth: maxWidth, padding: padding, child: body!);

    final content = onRefresh == null
        ? scrollable
        : RefreshIndicator(onRefresh: onRefresh!, child: scrollable);

    return Scaffold(
      appBar: bar,
      body: header == null
          ? content
          : Column(
              children: [
                AppContentWidth(
                  maxWidth: maxWidth,
                  padding: EdgeInsets.zero,
                  child: header!,
                ),
                Expanded(child: content),
              ],
            ),
      bottomNavigationBar: bottom,
      floatingActionButton: floatingActionButton,
    );
  }
}
