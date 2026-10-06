// 回归测试：`SDK.ping()` 与「地址改完是否真的打到新地址」。
//
// ping 是设置弹窗里「测试连接」的唯一依据，也是唯一能实证「改了端口就打到
// 新端口」的地方——只用 SharedPreferences 断言测不到网络层。这里起两个本地
// 桩服务器（不同端口）数请求，全程只绑回环地址，不出网。
import 'dart:convert';
import 'dart:io';

import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:flutter_test/flutter_test.dart';

/// 起一个假服务端：只有 `/api/comp/list_all` 回本项目信封，其余回 HTML。
/// 返回 [HttpServer] 与命中计数。
Future<({HttpServer server, List<String> hits})> _stub({
  bool jsonEnvelope = true,
}) async {
  final hits = <String>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    hits.add(req.uri.path);
    if (jsonEnvelope) {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'time': 0, 'code': 200, 'data': {}}));
    } else {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html>not a debate server</html>');
    }
    await req.response.close();
  });
  return (server: server, hits: hits);
}

void main() {
  group('SDK.ping', () {
    test('当前配置的地址可达时返回 true', () async {
      final a = await _stub();
      addTearDown(a.server.close);

      await ServerSettings.set(
        host: '127.0.0.1',
        port: a.server.port,
        https: false,
      );

      expect(await SDK.ping(), isTrue);
      expect(a.hits, ['/api/comp/list_all']);
    });

    test('改了端口就打到新端口，旧端口不再收到请求', () async {
      final a = await _stub();
      final b = await _stub();
      addTearDown(a.server.close);
      addTearDown(b.server.close);

      await ServerSettings.set(host: '127.0.0.1', port: a.server.port, https: false);
      expect(await SDK.ping(), isTrue);
      expect(a.hits, hasLength(1));
      expect(b.hits, isEmpty);

      await ServerSettings.set(host: '127.0.0.1', port: b.server.port, https: false);
      expect(await SDK.ping(), isTrue);
      expect(b.hits, hasLength(1));
      expect(a.hits, hasLength(1)); // 旧端口没有再被请求
    });

    test('端口没人监听时返回 false', () async {
      // 先占一个端口再释放，拿到一个确定没人监听的端口。
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final freePort = probe.port;
      await probe.close();

      await ServerSettings.set(host: '127.0.0.1', port: freePort, https: false);
      expect(await SDK.ping(), isFalse);
    });

    test('对面不是本项目服务端（返回 HTML）时返回 false', () async {
      final a = await _stub(jsonEnvelope: false);
      addTearDown(a.server.close);

      await ServerSettings.set(host: '127.0.0.1', port: a.server.port, https: false);
      expect(await SDK.ping(), isFalse);
    });

    test('baseUrl 覆盖：探测候选地址且不动当前配置', () async {
      final saved = await _stub();
      final candidate = await _stub();
      addTearDown(saved.server.close);
      addTearDown(candidate.server.close);

      await ServerSettings.set(
        host: '127.0.0.1',
        port: saved.server.port,
        https: false,
      );
      final current = ServerSettings.baseUrl;

      final ok = await SDK.ping(
        baseUrl: 'http://127.0.0.1:${candidate.server.port}',
      );

      expect(ok, isTrue);
      expect(candidate.hits, hasLength(1));
      expect(saved.hits, isEmpty);
      // 探测不能顺手把当前地址改掉。
      expect(ServerSettings.baseUrl, current);
    });
  });
}
