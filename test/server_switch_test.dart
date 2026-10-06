// 回归测试：换服务器后登录态的三种归宿。
//
// 关键是「新地址明确拒绝 token」和「新地址压根连不上」必须分开判定：前者该
// 登出，后者不该——网络问题销毁会话，会让用户改回正确地址后还得重新登录。
// 这段逻辑放在 `app/server_switch.dart` 就是为了能脱离 widget 树直接验证。
import 'dart:convert';
import 'dart:io';

import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/app/server_switch.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _token = 'tok-A';

/// 桩服务端：`/api/verify` 决定接受还是拒绝 token；顺带应答 WebSocket 升级，
/// 免得 `reconnect()` 的连接挂在那里拖住 `server.close()`。
Future<HttpServer> _stub({required bool acceptToken}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {}, onDone: () {}, cancelOnError: true);
      return;
    }
    // 请求体必须读完，否则连接会挂着。
    await utf8.decoder.bind(req).join();

    int code;
    Map<String, dynamic> data;
    switch (req.uri.path) {
      case '/api/verify':
        code = acceptToken ? 200 : 404;
        data = acceptToken ? {'userId': 7} : {};
      case '/api/profile':
        code = 200;
        data = {
          'userId': 7,
          'username': 'u7',
          'nickname': '七号',
          'bio': '',
          'email': 'u7@example.com',
          'createdAt': '2026-01-01 00:00:00',
          'updatedAt': '2026-01-01 00:00:00',
        };
      default:
        code = 404;
        data = {'error': 'stub'};
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'time': 0, 'code': code, 'data': data}));
    await req.response.close();
  });
  return server;
}

void main() {
  late AuthService auth;
  late ChatSocket socket;

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Cache.p = null;
    await Cache.init();
    await ServerSettings.load();

    auth = Get.put<AuthService>(AuthService());
    socket = Get.put<ChatSocket>(ChatSocket());
    // 手动构造登录态：走 login() 会真的去拉资料。
    auth.userObj.value = UserObj(token: _token);
    await Cache.p!.setString('jwtToken', _token);
  });

  tearDown(() {
    socket.onClose();
    Get.reset();
  });

  test('新地址拒绝旧 token → 登出', () async {
    final stub = await _stub(acceptToken: false);
    // force：keep-alive 连接会让普通的 close() 一直等下去。
    addTearDown(() => stub.close(force: true));

    await ServerSettings.set(host: '127.0.0.1', port: stub.port, https: false);

    expect(await ServerSwitch.apply(auth), ServerSwitchOutcome.rejected);
    expect(auth.isLoggedIn, isFalse);
    expect(Cache.p?.getString('jwtToken'), isNull);
  });

  test('新地址接受旧 token（只是换端口）→ 保留会话并重拉资料', () async {
    final stub = await _stub(acceptToken: true);
    addTearDown(() => stub.close(force: true));

    await ServerSettings.set(host: '127.0.0.1', port: stub.port, https: false);

    expect(await ServerSwitch.apply(auth), ServerSwitchOutcome.kept);
    expect(auth.isLoggedIn, isTrue);
    expect(Cache.p?.getString('jwtToken'), _token);
    // 资料必须按新服务端重新拉，不能沿用上一台的。
    expect(auth.userProfile.value?.userId, 7);
  });

  test('新地址连不上 → 不动登录态', () async {
    // 占一个端口再释放，得到一个确定没人监听的端口。
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close();

    await ServerSettings.set(host: '127.0.0.1', port: deadPort, https: false);

    expect(await ServerSwitch.apply(auth), ServerSwitchOutcome.unreachable);
    expect(Cache.p?.getString('jwtToken'), _token);
    expect(auth.isLoggedIn, isTrue);
  });

  test('未登录时切换只重建连接，返回 kept', () async {
    await auth.logout();
    await ServerSettings.set(host: '127.0.0.1', port: 8000, https: false);

    expect(await ServerSwitch.apply(auth), ServerSwitchOutcome.kept);
    expect(auth.isLoggedIn, isFalse);
  });
}
