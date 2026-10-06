import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Cache.p = null;
  });

  Future<void> initCache({Map<String, Object> values = const {}}) async {
    SharedPreferences.setMockInitialValues(values);
    await Cache.init();
  }

  group('ServerSettings.parse', () {
    test('裸主机补默认端口', () {
      final e = ServerSettings.parse('192.168.1.10');
      expect(e.host, '192.168.1.10');
      expect(e.port, 8000);
      expect(e.https, false);
    });

    test('host:port 拆出端口', () {
      final e = ServerSettings.parse('192.168.1.10:18000');
      expect(e.host, '192.168.1.10');
      expect(e.port, 18000);
    });

    test('http scheme 被识别', () {
      final e = ServerSettings.parse('http://example.com');
      expect(e.host, 'example.com');
      expect(e.port, 8000);
      expect(e.https, false);
    });

    test('https 且未给端口时落到 443', () {
      final e = ServerSettings.parse('https://example.com');
      expect(e.https, true);
      expect(e.port, 443);
    });

    test('https 显式端口优先', () {
      final e = ServerSettings.parse('https://example.com:8443');
      expect(e.https, true);
      expect(e.port, 8443);
    });

    test('丢掉路径与查询串', () {
      final e = ServerSettings.parse('http://example.com:9000/foo/bar?x=1');
      expect(e.host, 'example.com');
      expect(e.port, 9000);
    });

    test('空值回落内置默认', () {
      final e = ServerSettings.parse('   ');
      expect(e.host, '127.0.0.1');
      expect(e.port, 8000);
    });
  });

  group('ServerSettings 持久化', () {
    test('无持久化值时用内置默认', () async {
      await initCache();
      await ServerSettings.load();
      expect(ServerSettings.host.value, '127.0.0.1');
      expect(ServerSettings.port.value, 8000);
      expect(ServerSettings.baseUrl, 'http://127.0.0.1:8000');
      expect(ServerSettings.wsScheme, 'ws');
    });

    test('load 读回用户设置', () async {
      await initCache(values: {
        'server.host': '10.0.0.5',
        'server.port': 9000,
        'server.https': true,
      });
      await ServerSettings.load();
      expect(ServerSettings.baseUrl, 'https://10.0.0.5:9000');
      expect(ServerSettings.wsScheme, 'wss');
    });

    test('主机与端口必须成套存在', () async {
      await initCache(values: {'server.host': '10.0.0.5'});
      await ServerSettings.load();
      expect(ServerSettings.host.value, '127.0.0.1');
    });

    test('set 落盘，重新 load 后保留', () async {
      await initCache();
      await ServerSettings.load();

      expect(
        await ServerSettings.set(host: '10.0.0.5', port: 9000, https: false),
        true,
      );
      expect(ServerSettings.baseUrl, 'http://10.0.0.5:9000');
      expect(Cache.p?.getString('server.host'), '10.0.0.5');

      // 模拟重启：清掉内存态再读回。
      ServerSettings.host.value = '127.0.0.1';
      ServerSettings.port.value = 8000;
      await ServerSettings.load();
      expect(ServerSettings.baseUrl, 'http://10.0.0.5:9000');
    });

    test('地址未变化时 set 返回 false', () async {
      await initCache();
      await ServerSettings.load();
      expect(
        await ServerSettings.set(host: '127.0.0.1', port: 8000, https: false),
        false,
      );
    });

    test('reset 清掉用户设置回到默认', () async {
      await initCache(values: {
        'server.host': '10.0.0.5',
        'server.port': 9000,
        'server.https': true,
      });
      await ServerSettings.load();

      await ServerSettings.reset();
      expect(ServerSettings.baseUrl, 'http://127.0.0.1:8000');
      expect(Cache.p?.getString('server.host'), isNull);
    });
  });

  group('缓存按服务端隔离', () {
    test('cacheTag 折掉非字母数字', () async {
      await initCache();
      await ServerSettings.load();
      expect(ServerSettings.cacheTag, '127_0_0_1_8000');
    });

    test('换服务器后头像缓存的文件名与版本键都随之改变', () async {
      await initCache();
      await ServerSettings.load();

      final file1 = avatarCacheName(7);
      final ver1 = avatarVersionKey(7);

      await ServerSettings.set(host: '10.0.0.5', port: 9000, https: false);

      // 不同服务器上的 userId=7 是不同的人，绝不能共用同一份缓存。
      expect(avatarCacheName(7), isNot(file1));
      expect(avatarVersionKey(7), isNot(ver1));
      expect(avatarCacheName(7), contains('10_0_0_5_9000'));
    });
  });

  group('ServerSettings.validate', () {
    test('合法输入通过', () {
      expect(ServerSettings.validate(host: 'example.com', port: '8000'), isNull);
    });

    test('空地址被拒绝', () {
      expect(ServerSettings.validate(host: '', port: '8000'), isNotNull);
    });

    test('端口非数字被拒绝', () {
      expect(ServerSettings.validate(host: 'a.com', port: 'x'), isNotNull);
    });

    test('端口越界被拒绝', () {
      expect(ServerSettings.validate(host: 'a.com', port: '70000'), isNotNull);
    });
  });
}
