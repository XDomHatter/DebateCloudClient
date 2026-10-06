import 'package:debate_cloud/main.dart';
import 'package:debate_cloud/routed_apps/login/view.dart';
import 'package:debate_cloud/widgets/app_page_route.dart';
import 'package:debate_cloud/widgets/main_scaffold.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

class NavigationService extends GetxService {
  late RxList<GlobalKey<NavigatorState>> navigatorKeys;

  Widget? _pendingPage;
  int? _pendingTab;

  void init(RxList<GlobalKey<NavigatorState>> keys) {
    navigatorKeys = keys;
  }

  /// Tab 内跳转（带权限）
  Future toTabPage(int tabIndex, Widget page, {bool requireAuth = false}) async {
    if (requireAuth && !_checkAuth()) {
      _savePending(tabIndex, page);
      _goLogin();
      return;
    }
    changeTab(tabIndex);
    return navigatorKeys[tabIndex].currentState!.push(appPageRoute(page));
  }

  /// 全局跳转（带权限）
  Future toGlobal(Widget page, {bool requireAuth = false}) async {
    if (requireAuth && !_checkAuth()) {
      _savePending(null, page);
      _goLogin();
      return;
    }
    return Get.to(() => page);
  }

  /// 切换 Tab
  Future changeTab(int idx) async {
    Get.find<MainScaffoldController>().changeIndex(idx);
  }

  /// 登录后恢复跳转（关键）
  void resumePending() {
    if (_pendingPage == null) return;

    if (_pendingTab != null) {
      navigatorKeys[_pendingTab!].currentState!.push(appPageRoute(_pendingPage!));
    } else {
      Get.to(() => _pendingPage!);
    }

    _pendingPage = null;
    _pendingTab = null;
  }

  bool _checkAuth() {
    return Get.find<GlobalController>().userAuthed();
  }

  void _savePending(int? tab, Widget page) {
    _pendingTab = tab;
    _pendingPage = page;
  }

  void _goLogin() {
    Get.to(() => LoginView());
  }
}
