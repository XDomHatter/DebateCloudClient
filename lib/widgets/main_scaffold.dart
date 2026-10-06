import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/models/chat/view.dart';
import 'package:debate_cloud/models/home/view.dart';
import 'package:debate_cloud/models/profile/view.dart';
import 'package:debate_cloud/widgets/app_page_route.dart';
import 'package:debate_cloud/widgets/navbar.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MainScaffoldController extends GetxController {
  final tabIndex = 0.obs;
  final pages = [HomeView(), ChatHomePage(), ProfileView()];
  final navService = Get.find<NavigationService>();

  /// 每个 Tab 一个 Navigator。数量跟随 [pages]，避免多出无人使用的空 key。
  ///
  /// 不能在字段初始化器里读 `pages`（实例成员），只能在 onInit 里建。
  late final List<GlobalKey<NavigatorState>> navigatorKeys;

  @override
  void onInit() {
    super.onInit();
    navigatorKeys = List.generate(pages.length, (_) => GlobalKey<NavigatorState>());
    navService.init(navigatorKeys.obs);
  }

  // Switch tab; tapping the current tab again pops it back to its root page.
  void changeIndex(int index) {
    if (tabIndex.value == index) {
      navigatorKeys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      tabIndex.value = index;
    }
  }
}

class MainScaffold extends StatelessWidget {
  MainScaffold({super.key});

  final controller = Get.put(MainScaffoldController());

  @override
  Widget build(BuildContext context) {
    final mainNavController = Get.put(MainNavController());
    return ResponsiveLayout(
      compact: _buildCompact(),
      // 平板 / 小窗口（600–1023）也用侧边导航：这个宽度下底部导航会占掉
      // 一整条内容高度，而左侧 72px 的图标栏几乎不花钱。
      medium: _buildExpanded(context, mainNavController),
      expanded: _buildExpanded(context, mainNavController),
    );
  }

  /// 每个 Tab 一个独立 Navigator，切换时保留浏览栈。
  Widget _buildBody() {
    return IndexedStack(
      index: controller.tabIndex.value,
      children: [
        for (var i = 0; i < controller.pages.length; i++)
          Navigator(
            key: controller.navigatorKeys[i],
            onGenerateRoute: (_) => appPageRoute(controller.pages[i]),
          ),
      ],
    );
  }

  Widget _buildCompact() {
    return Obx(
      () => Scaffold(
        body: _buildBody(),
        bottomNavigationBar: MainNav(
          selectedIndex: controller.tabIndex.value,
          onDestinationSelected: controller.changeIndex,
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, MainNavController navController) {
    // 只有桌面宽度才允许把导航展开到 168px；600–1023 这一档收起更划算。
    // 这里读 MediaQuery 会登记依赖，窗口缩放时重新求值。
    final canExtend =
        MainNavRail.canExtendAt(MediaQuery.sizeOf(context).width);
    return Obx(
      () => Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MainNavRail(
              selectedIndex: controller.tabIndex.value,
              onDestinationSelected: controller.changeIndex,
              onOpenChatSubPage: navController.openChatSubPage,
              onOpenServerSettings: () => ServerSettingsDialog.open<void>(),
              extended: navController.extended.value,
              canExtend: canExtend,
              onToggleExtended: navController.toggleExtended,
            ),
            VerticalDivider(width: 1, thickness: 1, color: context.appBorderColor),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
