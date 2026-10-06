// 回归测试：按真实故障路径复现——**已登录 + 服务端不可用**。
//
// 出过的真实问题：入口原先挂在页面内容里。已登录时登录页不可达，而个人页与
// 赛事中心在服务端不可用时会整块渲染成 AppEmptyState 错误态，入口跟着一起
// 消失，用户完全无法改地址。修法是把入口挪到框架层（脚手架 AppBar + 导航）。
//
// 两个实现细节（都是踩过的坑）：
// - **不能直接 await ServerSettings.set**：它要写 SharedPreferences，在
//   testWidgets 的 fake-async 里没有 pump 就 flush 不掉，会直接挂死。这里
//   只改内存态（持久化由 server_settings_test.dart 覆盖）。
// - **服务端用本地桩而不是空闲端口**：真实网络在 fake-async 下不返回，
//   `pumpWidget` 会卡住。桩统一回 `code: 500`——既不是 200（拿到资料）也不是
//   404（被当成登录态失效而登出），正好落在「登录态还在、资料加载失败」这一态。
import 'dart:convert';
import 'dart:io';

import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/models/home/view.dart';
import 'package:debate_cloud/models/profile/view.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个「坏了」的服务端：任何接口都回 code 500。
Future<HttpServer> _brokenServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  // 默认 idleTimeout 会挂一个 2 分钟的周期 Timer，widget 测试结束时会因
  // `!timersPending` 直接判失败。测试桩不需要它。
  server.idleTimeout = null;
  server.listen((req) async {
    await utf8.decoder.bind(req).join();
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'time': 0,
        'code': 500,
        'data': {'error': 'server down'},
      }));
    await req.response.close();
  });
  return server;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) throw Exception('条件在 $timeout 内未成立');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Cache.p = null;
    await Cache.init();
    await ServerSettings.load();
    // 手动构造登录态：已登录是复现这个 bug 的前提（登录页这会儿根本不可达）。
    Get.put<AuthService>(AuthService()).userObj.value = UserObj(token: 'tok');
  });

  tearDown(Get.reset);

  testWidgets('服务端不可用 + 已登录：我的页面仍能从 AppBar 改地址', (tester) async {
    final stub = await _brokenServer();
    addTearDown(() => stub.close(force: true));

    ServerSettings.host.value = '127.0.0.1';
    ServerSettings.port.value = stub.port;
    ServerSettings.https.value = false;

    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light(), home: ProfileView()),
    );
    // 等页面落进错误态。
    await _pumpUntil(
      tester,
      () => find.textContaining('可在右上角修改').evaluate().isNotEmpty,
    );

    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('服务器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务端不可用 + 已登录：赛事中心仍能从 AppBar 改地址', (tester) async {
    final stub = await _brokenServer();
    addTearDown(() => stub.close(force: true));

    ServerSettings.host.value = '127.0.0.1';
    ServerSettings.port.value = stub.port;
    ServerSettings.https.value = false;

    await tester.pumpWidget(
      GetMaterialApp(theme: AppTheme.light(), home: HomeView()),
    );
    await _pumpUntil(
      tester,
      () => find.textContaining('可在右上角修改').evaluate().isNotEmpty,
    );

    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('服务器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
