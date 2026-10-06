// 回归测试：设置弹窗的「预填 → 校验 → 落盘 → 联动 → 关窗」链路。
//
// 单看 ServerSettings 的数据层测不到这段：地址改完之后必须重建 WebSocket、
// 未登录时不能去调 AuthService，这些副作用最容易在重构中静默丢失。
// 测试全程不触网（未登录态下 ChatSocket 只会拆除连接）。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _boot(WidgetTester tester) async {
  await tester.pumpWidget(
    GetMaterialApp(theme: AppTheme.light(), home: const Scaffold(body: SizedBox())),
  );
  // ChatSocket.onInit 会 Get.find<AuthService>()，必须先注册。
  Get.put<AuthService>(AuthService());
  Get.put<ChatSocket>(ChatSocket());
  await tester.pump();

  Get.dialog<void>(const ServerSettingsDialog());
  await tester.pumpAndSettle();
}

/// 关窗会弹 snackbar：它挂着一个 3 秒的消失定时器，测试结束前还有 pending
/// timer 会被框架判为失败，所以这里直接推进到定时器触发。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Cache.p = null;
    await Cache.init();
    await ServerSettings.load();
  });

  testWidgets('预填当前地址，保存后落盘并关闭弹窗', (tester) async {
    await _boot(tester);

    expect(find.text('服务器设置'), findsOneWidget);
    expect(find.text('127.0.0.1'), findsOneWidget);
    expect(find.text('8000'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '127.0.0.1'), '10.0.0.5');
    await tester.enterText(find.widgetWithText(TextField, '8000'), '9000');
    await tester.tap(find.text('保存'));
    await _settle(tester);

    expect(ServerSettings.host.value, '10.0.0.5');
    expect(ServerSettings.port.value, 9000);
    expect(ServerSettings.baseUrl, 'http://10.0.0.5:9000');
    expect(Cache.p?.getString('server.host'), '10.0.0.5');
    expect(Cache.p?.getInt('server.port'), 9000);

    // 弹窗已关闭，且没有遗留布局异常。
    expect(find.text('服务器设置'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非法端口被拦下，不写盘也不关窗', (tester) async {
    await _boot(tester);

    await tester.enterText(find.widgetWithText(TextField, '8000'), '70000');
    await tester.tap(find.text('保存'));
    await _settle(tester);

    expect(find.text('服务器设置'), findsOneWidget);
    expect(ServerSettings.port.value, 8000);
    expect(Cache.p?.getString('server.host'), isNull);
  });

  testWidgets('恢复默认会清掉用户设置', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server.host': '10.0.0.5',
      'server.port': 9000,
      'server.https': false,
    });
    Cache.p = null;
    await Cache.init();
    await ServerSettings.load();
    expect(ServerSettings.baseUrl, 'http://10.0.0.5:9000');

    await _boot(tester);
    await tester.tap(find.text('恢复默认'));
    await _settle(tester);

    expect(ServerSettings.baseUrl, 'http://127.0.0.1:8000');
    expect(Cache.p?.getString('server.host'), isNull);
    expect(find.text('服务器设置'), findsNothing);
  });
}
