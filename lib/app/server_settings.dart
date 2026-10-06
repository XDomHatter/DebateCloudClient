import 'package:get/get.dart';

import 'cache.dart';

/// 一个服务端地址：主机 + 端口 + 是否 HTTPS。
typedef ServerEndpoint = ({String host, int port, bool https});

/// 服务端地址配置 —— 全应用**唯一真源**。
///
/// 来源按优先级从高到低：
/// 1. 用户在设置界面填写的值（SharedPreferences）；
/// 2. 编译期注入的出厂默认值 `--dart-define=SERVER_IP=... SERVER_PORT=...`；
/// 3. 内置默认 `http://127.0.0.1:8000`。
///
/// 之所以必须收敛到一处：`SDK` 的 HTTP 请求与 `ChatSocket` 的 WebSocket
/// 地址都从 [baseUrl] 派生，若各存一份常量，运行时改地址就会出现「HTTP 走
/// 新地址、WebSocket 还连旧地址」的错配。
abstract final class ServerSettings {
  static const String _keyHost = 'server.host';
  static const String _keyPort = 'server.port';
  static const String _keyHttps = 'server.https';

  static const String _fallbackHost = '127.0.0.1';
  static const int _fallbackPort = 8000;

  /// 编译期注入值。未注入时为空串 / 0（`fromEnvironment` 的缺省值）。
  static const String _buildHost = String.fromEnvironment('SERVER_IP');
  static const int _buildPort = int.fromEnvironment('SERVER_PORT');

  static final RxString host = _fallbackHost.obs;
  static final RxInt port = _fallbackPort.obs;
  static final RxBool https = false.obs;

  /// 编译期（或内置）默认端点，供「恢复默认」使用。
  static ServerEndpoint get buildDefault => parse(
    _buildHost,
    fallbackPort: _buildPort > 0 ? _buildPort : _fallbackPort,
  );

  /// 形如 `http://192.168.1.10:8000`，不带结尾斜杠。
  static String get baseUrl =>
      '${https.value ? 'https' : 'http'}://${host.value}:${port.value}';

  /// WebSocket scheme，始终跟随 HTTP scheme 推导。
  static String get wsScheme => https.value ? 'wss' : 'ws';

  /// 给界面展示的 `host:port`。
  static String get display => '${host.value}:${port.value}';

  /// 服务端标记，用于隔离「只在单个服务端内唯一」的本地缓存（如按 `userId`
  /// 命名的好友头像）。非字母数字一律折成 `_`，避免 IP/域名里的 `.` 影响
  /// 文件名与偏好键。
  static String get cacheTag {
    final raw = '${host.value}_${port.value}';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  }

  /// 把任意端点拼成可用的 base URL。
  static String urlOf(ServerEndpoint e) =>
      '${e.https ? 'https' : 'http'}://${e.host}:${e.port}';

  /// 在 [Cache.init] 之后调用：用户设置优先，其次编译期默认。
  static Future<void> load() async {
    _apply(_readSaved() ?? buildDefault);
  }

  /// 写入并落盘。返回是否真的发生了变化（未变化时调用方无需重建连接）。
  static Future<bool> set({
    required String host,
    required int port,
    required bool https,
  }) async {
    final next = (host: host.trim(), port: port, https: https);
    if (!_apply(next)) return false;
    final p = Cache.p;
    await p?.setString(_keyHost, next.host);
    await p?.setInt(_keyPort, next.port);
    await p?.setBool(_keyHttps, next.https);
    return true;
  }

  /// 清除用户设置，回落到编译期 / 内置默认值。
  static Future<void> reset() async {
    final p = Cache.p;
    await p?.remove(_keyHost);
    await p?.remove(_keyPort);
    await p?.remove(_keyHttps);
    _apply(buildDefault);
  }

  static ServerEndpoint? _readSaved() {
    final p = Cache.p;
    if (p == null) return null;
    final h = p.getString(_keyHost);
    final port = p.getInt(_keyPort);
    // 主机与端口必须成套存在，缺一半就当没设置过。
    if (h == null || h.isEmpty || port == null) return null;
    return (host: h, port: port, https: p.getBool(_keyHttps) ?? false);
  }

  /// 只改内存态。返回是否有变化。
  static bool _apply(ServerEndpoint e) {
    if (host.value == e.host && port.value == e.port && https.value == e.https) {
      return false;
    }
    host.value = e.host;
    port.value = e.port;
    https.value = e.https;
    return true;
  }

  static final RegExp _schemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
  static final RegExp _hostPattern = RegExp(r'^[A-Za-z0-9._\-]+$');

  /// 解析用户输入或 dart-define：容忍 scheme、路径、查询串与 `host:port`。
  ///
  /// 未显式给端口时：`https` 用 443，其余用 [fallbackPort]（默认 8000），
  /// 这样 `--dart-define=SERVER_IP=xdomhatter.tech` 仍能落在开发端口上。
  /// 不支持 IPv6 字面量（`[::1]`），需配合域名使用。
  static ServerEndpoint parse(String raw, {int fallbackPort = _fallbackPort}) {
    var value = raw.trim();
    var https = false;

    final scheme = _schemePattern.firstMatch(value);
    if (scheme != null) {
      final s = scheme[0]!.toLowerCase();
      https = s.startsWith('https') || s.startsWith('wss');
      value = value.substring(scheme.end);
    }

    // 丢掉路径 / 查询 / 锚点，只留 authority。
    final cut = value.indexOf(RegExp(r'[/?#]'));
    if (cut >= 0) value = value.substring(0, cut);

    var port = fallbackPort;
    var explicitPort = false;
    final colon = value.lastIndexOf(':');
    if (colon > 0 && colon < value.length - 1) {
      final n = int.tryParse(value.substring(colon + 1));
      if (n != null) {
        port = n;
        explicitPort = true;
        value = value.substring(0, colon);
      }
    }

    value = value.trim();
    if (!explicitPort && https) port = 443;
    return (
      host: value.isEmpty ? _fallbackHost : value,
      port: port,
      https: https,
    );
  }

  /// 表单校验。返回错误文案，合法时返回 `null`。
  static String? validate({required String host, required String port}) {
    final h = host.trim();
    if (h.isEmpty) return '请输入服务器地址';
    if (!_hostPattern.hasMatch(parse(h).host)) {
      return '地址只能包含字母、数字、点、连字符';
    }
    final p = int.tryParse(port.trim());
    if (p == null) return '端口必须是数字';
    if (p < 1 || p > 65535) return '端口需在 1–65535 之间';
    return null;
  }

  /// 用表单当前值算出一个端点：主机里写了 `host:port` 时以它为准。
  static ServerEndpoint fromForm({
    required String host,
    required String port,
    required bool https,
  }) {
    final fallback = int.tryParse(port.trim()) ?? _fallbackPort;
    final e = parse(host, fallbackPort: fallback);
    return (host: e.host, port: e.port, https: https || e.https);
  }
}
