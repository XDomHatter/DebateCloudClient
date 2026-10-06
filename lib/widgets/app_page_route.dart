import 'package:debate_cloud/app/app_design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 全站统一的页面转场：淡入 + 轻微上移。
///
/// Get 的 `Get.to` 由 `GetMaterialApp.defaultTransition` 统一控制；但 Tab 内
/// 的跳转走的是各 Tab 自己的 `Navigator.push`（见 `MainScaffoldController`
/// 与 `NavigationService`），Get 的转场配置管不到，必须显式给出同一个转场，
/// 否则同一款 App 里两种跳转手感不一致。
///
/// 位移只做 2% 高度：够让人感知到"推入"的方向，又不至于在桌面端显得晃。
Route<T> appPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, _, _) => page,
    transitionDuration: AppDesign.normal,
    reverseTransitionDuration: AppDesign.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _buildTransitions(animation, child),
  );
}

/// 给 `GetMaterialApp.customTransition` 用：让 `Get.to` 的转场与
/// [appPageRoute] 保持同一手感。
class AppGetTransition extends CustomTransition {
  AppGetTransition();

  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _buildTransitions(animation, child);
}

Widget _buildTransitions(Animation<double> animation, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.02),
        end: Offset.zero,
      ).animate(curved),
      child: child,
    ),
  );
}
