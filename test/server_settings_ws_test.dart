// 回归测试：WebSocket 真实握手 + 改地址后 `ChatSocket.reconnect()` 打到新端口。
//
// 这是整个功能里唯一能实证「长连接也跟着走新地址」的地方：HTTP 侧有
// probe 测试，但 WebSocket 的 URL 是在 `ChatSocket._connect()` 里现拼的，
// 私有方法测不到，只能靠真握手。这里用 `WebSocketTransformer` 起两个桩
// （不同端口）数升级请求，全程只绑回环地址。
import 'dart:convert';
import 'dart:io';

import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 桩服务端：WS 升级请求记录 path / token；普通 POST 回未读数信封，
/// 免得 `refreshUnread()` 走异常分支干扰断言。
Future<({HttpServer server, List<String> paths, List<String> tokens})> _stub() async {
  final paths = <String>[];
  final tokens = <String>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      paths.add(req.uri.path);
      tokens.add(req.uri.queryParameters['token'] ?? '');
      final ws = await WebSocketTransformer.upgrade(req);
      // 保持连接，别让客户端立刻收到 done。
      ws.listen((_) {}, onDone: () {}, cancelOnError: true);
      return;
    }
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'time': 0,
        'code': 200,
        'data': {'messages': 0, 'friendRequests': 0, 'notifications': 0},
      }));
    await req.response.close();
  });
  return (server: server, paths: paths, tokens: tokens);
}

/// 真实网络是异步的，轮询等条件成立。
Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw Exception('条件在 $timeout 内未成立');
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('登录即连；改地址后 reconnect 打到新端口，旧端口不再被连', () async {
    final a = await _stub();
    final b = await _stub();
    addTearDown(() async {
      Get.reset();
      await a.server.close();
      await b.server.close();
    });

    Get.reset();
    final auth = Get.put<AuthService>(AuthService());
    await ServerSettings.set(host: '127.0.0.1', port: a.server.port, https: false);

    // ChatSocket 靠 ever(auth.userObj) 跟随登录态，所以先注册再给 token。
    final socket = Get.put<ChatSocket>(ChatSocket());
    auth.userObj.value = UserObj(token: 'token-A');

    await _waitFor(() => socket.status.value == ChatConnStatus.connected);
    expect(a.paths, ['/ws/chat']);
    expect(a.tokens, ['token-A']);
    expect(b.paths, isEmpty);

    // 换端口并重建：新连接必须落在 b，a 不再收到任何升级请求。
    await ServerSettings.set(host: '127.0.0.1', port: b.server.port, https: false);
    socket.reconnect();

    await _waitFor(() => b.paths.isNotEmpty);
    await _waitFor(() => socket.status.value == ChatConnStatus.connected);

    expect(b.paths, ['/ws/chat']);
    expect(b.tokens, ['token-A']);
    expect(a.paths, hasLength(1), reason: '旧端口不应再被连接');
  });
}
