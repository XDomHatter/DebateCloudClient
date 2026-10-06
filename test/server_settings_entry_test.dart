// 回归测试：两个「服务器设置」入口确实接上了。
//
// 入口本身只是一个 AppBar 图标和一张卡片的 onTap，`flutter analyze` 查不出
// 「没接」或「接到了别的弹窗」，这里各点一次把链路钉住：登录页（未登录也要
// 能改）与个人页访客态。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/models/profile/view.dart';
import 'package:debate_cloud/routed_apps/login/view.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Cache.p = null;
    await Cache.init();
    await ServerSettings.load();
    // ChatSocket.onInit 会 Get.find<AuthService>()，顺序不能反。
    Get.put<AuthService>(AuthService());
    Get.put<NavigationService>(NavigationService());
    Get.put<ChatSocket>(ChatSocket());
  });

  testWidgets('登录页 AppBar 齿轮能打开设置弹窗', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light(), home: LoginView()),
    );
    await tester.pumpAndSettle();

    // 常驻地址回显：连不上时能一眼确认打到哪台机器。
    expect(find.text('当前服务器 127.0.0.1:8000'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('服务器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('个人页（未登录）服务器卡片能打开设置弹窗', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light(), home: ProfileView()),
    );
    await tester.pumpAndSettle();

    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('127.0.0.1:8000'), findsOneWidget);

    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();

    expect(find.text('服务器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
