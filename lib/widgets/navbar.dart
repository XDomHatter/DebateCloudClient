import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/routed_apps/chat/contacts_view.dart';
import 'package:debate_cloud/routed_apps/chat/friend_requests_view.dart';
import 'package:debate_cloud/routed_apps/chat/notifications_view.dart';
import 'package:debate_cloud/widgets/main_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MainNavController extends GetxController {
  /// 侧边导航是否展开。
  ///
  /// 只有屏幕宽度 ≥ [AppDesign.bpRailExtended] 时这份状态才会被采纳
  /// （见 [MainNavRail.canExtend]），窄屏永远是收起的图标栏。
  final extended = true.obs;

  /// 懒取 [MainScaffoldController]：构造期就 `Get.find` 会把整个主框架
  /// （含 HomeView 及其网络请求）拖进来，导致导航没法单独做 widget 测试。
  MainScaffoldController get scaffold => Get.find<MainScaffoldController>();

  void toggleExtended() => extended.toggle();

  void changeIndex(int idx) => scaffold.changeIndex(idx);

  /// 打开消息页之下的二级页面（通讯录 / 好友申请 / 通知）。
  ///
  /// 走 [NavigationService.toTabPage] 推入消息 Tab 的 Navigator：
  /// 这样返回时回到的是消息列表，而不是顶层；未登录时会被拦到登录页
  /// 并在登录后自动恢复跳转。
  void openChatSubPage(Widget page) {
    scaffold.navService.toTabPage(1, page, requireAuth: true);
  }
}

/// 移动端：底部导航。
///
/// 纯展示组件——只吃 [selectedIndex] 与回调，不碰任何 Controller，
/// 这样既能被 [MainScaffold] 复用，也能单独测。
class MainNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const MainNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: context.appBorderColor)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '赛事',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '消息',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 桌面端：左侧常驻导航。
///
/// 两种形态：
/// - 收起（[AppDesign.railWidth]，72）：居中的正方形图标按钮，600–1023 固定用它；
/// - 展开（[AppDesign.railWidthExtended]，168）：图标 + 文字，并在下方列出
///   消息页的二级入口（通讯录 / 好友申请 / 通知），省掉「先点消息再找入口」。
///
/// 是否允许展开由 [canExtend] 决定，[MainScaffold] 按屏幕宽度传入。
///
/// 一级 Tab 与二级入口共用 [_railItem] 的扁平行（[AppDesign.railItemHeight]）：
/// 之前二级入口是 48px 的 `ListTile`、一级是 32px 的 `NavigationRail` 指示器，
/// 出现了「子项比父项还高」的倒挂层级。
class MainNavRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 打开消息二级页面（展开态才有入口）。
  final void Function(Widget page) onOpenChatSubPage;

  /// 打开服务器设置弹窗。
  ///
  /// 导航是唯一**不受页面状态影响**的位置：服务端下线时页面内容多半是错误态，
  /// 挂在内容里的入口会跟着消失，而这里始终在。
  final VoidCallback? onOpenServerSettings;

  /// 用户是否希望展开；只有 [canExtend] 为真时才生效。
  final bool extended;

  /// 屏幕宽度是否撑得起展开态。
  final bool canExtend;

  final VoidCallback? onToggleExtended;

  const MainNavRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onOpenChatSubPage,
    this.onOpenServerSettings,
    this.extended = false,
    this.canExtend = false,
    this.onToggleExtended,
  });

  /// 某个宽度是否撑得起展开态。
  ///
  /// 抽成静态纯函数是为了能直接单测——否则得先搭起整个 MainScaffold
  /// （连带 HomeView 的控制器与网络请求）。
  static bool canExtendAt(double width) => width >= AppDesign.bpRailExtended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showExtended = canExtend && extended;
    return AnimatedContainer(
      duration: AppDesign.normal,
      // 宽度由外层统一动画，内部的展开/收起只负责内容淡入淡出，
      // 交给子级各自动画宽度会与这里的曲线对不齐。
      width: showExtended ? AppDesign.railWidthExtended : AppDesign.railWidth,
      color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _brand(context, showExtended),
            const SizedBox(height: AppDesign.spaceS),
            _railItem(
              context: context,
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: '赛事',
              selected: selectedIndex == 0,
              extended: showExtended,
              onTap: () => onDestinationSelected(0),
            ),
            const SizedBox(height: AppDesign.railItemSpacing),
            _railItem(
              context: context,
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble,
              label: '消息',
              selected: selectedIndex == 1,
              extended: showExtended,
              onTap: () => onDestinationSelected(1),
            ),
            const SizedBox(height: AppDesign.railItemSpacing),
            _railItem(
              context: context,
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: '我的',
              selected: selectedIndex == 2,
              extended: showExtended,
              onTap: () => onDestinationSelected(2),
            ),
            if (showExtended) ..._chatEntries(context),
            const Spacer(),
            // 服务器入口放在导航里而不是页面里：连不上服务器时，页面内容往往
            // 整块变成错误态，挂在内容里的入口会跟着一起消失。
            if (onOpenServerSettings != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.spaceXS),
                child: _railItem(
                  context: context,
                  icon: Icons.dns_outlined,
                  selectedIcon: Icons.dns,
                  label: '服务器',
                  selected: false,
                  extended: showExtended,
                  secondary: true,
                  onTap: onOpenServerSettings!,
                ),
              ),
            if (canExtend) _toggle(context, showExtended),
            const SizedBox(height: AppDesign.spaceS),
          ],
        ),
      ),
    );
  }

  Widget _brand(BuildContext context, bool extended) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppDesign.spaceL,
        bottom: AppDesign.spaceS,
      ),
      child: extended
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _logo(scheme),
                const SizedBox(width: AppDesign.spaceXS),
                Flexible(
                  child: Text(
                    'Debate Cloud',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            )
          // 收起态省掉两行小字：72px 里它们必然被压成两截，
          // 品牌名交给 Tooltip 兜住即可。
          //
          // 必须显式 Center：`Padding` 的定位是 `offset = padding.topLeft`，
          // 不套一层居中就会贴左边缘。
          : Center(
              child: AppTooltip(message: 'Debate Cloud', child: _logo(scheme)),
            ),
    );
  }

  Widget _logo(ColorScheme scheme) {
    return Container(
      width: AppDesign.railLogoSize,
      height: AppDesign.railLogoSize,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppDesign.radiusS),
      ),
      child: Icon(Icons.forum_outlined, size: 18, color: scheme.onPrimary),
    );
  }

  /// 一二级共用的扁平行。
  ///
  /// 选中态用 `primaryContainer` 药丸代替 `NavigationRail` 的指示器：
  /// 指示器高度是写死的 32，撑不到这里要的 40，而且左右各留 8px 让
  /// 药丸贴不到边，看着像悬浮的色块。
  Widget _railItem({
    required BuildContext context,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required bool extended,
    required VoidCallback onTap,
    bool secondary = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final contentColor = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    // 收起态没有文字撑着，图标放大一档才填得满 40 的方块。
    final iconSize = secondary ? 18.0 : (extended ? 20.0 : 22.0);
    Widget item = AnimatedContainer(
            duration: AppDesign.fast,
            // 收起态必须是正方形：通栏会变成 56×40 的横条，图标孤零零浮在
            // 中间就像被拉长了（600–1023 这一档正是这个形态）。
            width: extended ? null : AppDesign.railItemHeight,
            height: AppDesign.railItemHeight,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDesign.radiusM),
            ),
            child: Material(
              // 透明 Material：让 InkWell 的水波纹画在自己的层级上，
              // 而不是被上面的 decoration 盖住。
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppDesign.radiusM),
                onTap: onTap,
                child: extended
                    ? Row(
                        children: [
                          const SizedBox(width: AppDesign.spaceS),
                          Icon(
                            selected ? selectedIcon : icon,
                            size: iconSize,
                            color: contentColor,
                          ),
                          const SizedBox(width: AppDesign.spaceS),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: (secondary
                                      ? text.bodyMedium
                                      : text.labelLarge)
                                  ?.copyWith(color: contentColor),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Icon(
                          selected ? selectedIcon : icon,
                          size: iconSize,
                          color: contentColor,
                        ),
                      ),
              ),
            ),
          );
    final tile = Semantics(selected: selected, button: true, child: item);
    // 展开态文字已经可见，再挂 tooltip 只会挡住点击；收起态没有文字，
    // 必须用 tooltip 兜住语义。
    if (!extended) {
      // 居中：方块只有 40，栏宽 72，不居中就会贴左边缘。
      return Center(child: AppTooltip(message: label, child: tile));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceXS),
      child: tile,
    );
  }

  /// 二级入口：消息页之下的三个页面。
  List<Widget> _chatEntries(BuildContext context) {
    return [
      const SizedBox(height: AppDesign.spaceS),
      Divider(
        height: 1,
        thickness: 1,
        color: context.appBorderColor,
        indent: AppDesign.spaceM,
        endIndent: AppDesign.spaceM,
      ),
      const SizedBox(height: AppDesign.spaceXS),
      _railItem(
        context: context,
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_outlined,
        label: '通讯录',
        selected: false,
        extended: true,
        secondary: true,
        onTap: () => onOpenChatSubPage(const ContactsPage()),
      ),
      const SizedBox(height: AppDesign.railItemSpacing),
      _railItem(
        context: context,
        icon: Icons.person_add_alt_outlined,
        selectedIcon: Icons.person_add_alt_outlined,
        label: '好友申请',
        selected: false,
        extended: true,
        secondary: true,
        onTap: () => onOpenChatSubPage(const FriendRequestsPage()),
      ),
      const SizedBox(height: AppDesign.railItemSpacing),
      _railItem(
        context: context,
        icon: Icons.notifications_none,
        selectedIcon: Icons.notifications_none,
        label: '通知',
        selected: false,
        extended: true,
        secondary: true,
        onTap: () => onOpenChatSubPage(const NotificationsPage()),
      ),
    ];
  }

  Widget _toggle(BuildContext context, bool extended) {
    final scheme = Theme.of(context).colorScheme;
    final button = AppTooltip(
      message: extended ? '收起导航' : '展开导航',
      child: SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          // 默认 IconButton 是 48 的正方形，在 72px 的收起栏里偏重。
          //
          // 光给 `constraints` 不够：`_InputPadding` 仍会按样式里的
          // minimumSize(48) 撑外框，只有外层再压一个 tight 尺寸才收得住。
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Icon(
            extended ? Icons.chevron_left : Icons.chevron_right,
            color: scheme.onSurfaceVariant,
          ),
          onPressed: onToggleExtended,
        ),
      ),
    );
    // 收起态与图标列同心（栏宽 72 的中线 x=36）；展开态对齐图标槽
    // （12 左内边距 + 按钮半宽 = x=30），居中反而会跑到栏中间。
    //
    // `Align` / `Center` 不是装饰：外层 Column 是 stretch，给下来的是
    // **tight** 宽度，`BoxConstraints.tightFor(36)` 会被 `enforce` 反向
    // clamp 回栏宽（按钮被拉成 156×48）。只有换成松散约束，36 才生效。
    return extended
        ? Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: AppDesign.spaceS),
              child: button,
            ),
          )
        : Center(child: button);
  }
}
