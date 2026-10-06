import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/app/server_switch.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 服务端地址设置弹窗（登录页与个人页共用）。
///
/// 「测试连接」用**表单里的候选地址**探测，不依赖当前已保存的值，因此
/// 可以先试再存；探测走 `SDK.ping`，打的是无需登录的公开接口。
class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  /// 打开弹窗的统一入口。
  static Future<T?> open<T>() => Get.dialog<T>(const ServerSettingsDialog());

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late bool _https;

  bool _saving = false;
  bool _testing = false;
  String? _error;

  /// 探测结果：`null` 表示还没测过。
  bool? _probe;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: ServerSettings.host.value);
    _portCtrl = TextEditingController(text: ServerSettings.port.value.toString());
    _https = ServerSettings.https.value;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '服务器设置',
      // 必须可滚动：两个输入框 + 开关 + 提示 + 测试按钮，在矮窗口（如 420px
      // 高）会溢出（金图测试实测溢出 138px）。滚的是内容区，操作按钮始终露在
      // 外面。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // 主机与端口同行：在窄窗口（如 520×420）下叠两行要靠滚动才能看完
          // 整块，挪到一行省约 68px，让开关和「测试连接」也直接放得下。
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'IP 或域名',
                    prefixIcon: Icon(Icons.dns_outlined, size: 20),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clear(),
                ),
              ),
              const SizedBox(width: AppDesign.spaceS),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(labelText: '端口'),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _clear(),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            // 副标题「WebSocket 走 wss/ws」冗余：HTTPS 一开 WS 必然跟着切，
            // 删掉可以省下约 20px，让短窗口也能直接看完整个弹窗。
            title: const Text('使用 HTTPS'),
            value: _https,
            onChanged: (v) => setState(() {
              _https = v;
              _probe = null;
            }),
          ),
          if (_error != null) _hint(_error!, true),
          if (_error == null && _probe != null)
            _hint(_probe! ? '连接成功，服务端可访问' : '无法连接该地址', !_probe!),
          const SizedBox(height: AppDesign.spaceXS),
          // 裸按钮放进 Row 会被主题的 Size.fromHeight 撑成无限宽，这里用
          // Align 先把它收成自身尺寸。
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _testing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _test,
                    icon: const Icon(Icons.wifi_tethering_outlined, size: 18),
                    label: const Text('测试连接'),
                  ),
          ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('恢复默认')),
        TextButton(onPressed: () => Get.back<void>(), child: const Text('取消')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _hint(String message, bool isError) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.spaceXS),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: isError ? scheme.error : scheme.primary),
      ),
    );
  }

  void _clear() {
    if (_error == null && _probe == null) return;
    setState(() {
      _error = null;
      _probe = null;
    });
  }

  ServerEndpoint _endpoint() => ServerSettings.fromForm(
    host: _hostCtrl.text,
    port: _portCtrl.text,
    https: _https,
  );

  Future<void> _test() async {
    final error = ServerSettings.validate(
      host: _hostCtrl.text,
      port: _portCtrl.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _probe = null;
      _testing = true;
    });
    final ok = await SDK.ping(baseUrl: ServerSettings.urlOf(_endpoint()));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = ok;
    });
  }

  Future<void> _save() async {
    final error = ServerSettings.validate(
      host: _hostCtrl.text,
      port: _portCtrl.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    final e = _endpoint();
    final changed = await ServerSettings.set(
      host: e.host,
      port: e.port,
      https: e.https,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    // 必须先关窗再提示：GetX 的 Get.back() 在 snackbar 打开时会先去关
    // snackbar 然后直接 return（closeOverlays 默认 false），顺序反了弹窗
    // 就再也关不掉。
    Get.back<void>();
    if (changed) await _afterChange();
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    final before = ServerSettings.baseUrl;
    await ServerSettings.reset();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _hostCtrl.text = ServerSettings.host.value;
      _portCtrl.text = ServerSettings.port.value.toString();
      _https = ServerSettings.https.value;
      _error = null;
      _probe = null;
    });
    // 同上：先关窗，再发提示。
    Get.back<void>();
    // 本来就是默认值时不做联动，避免无谓地重建连接。
    if (ServerSettings.baseUrl != before) await _afterChange();
  }

  /// 地址真的变了之后的联动，具体处置见 [ServerSwitch.apply]。
  Future<void> _afterChange() async {
    await ServerSwitch.apply(Get.find<AuthService>());
  }
}
