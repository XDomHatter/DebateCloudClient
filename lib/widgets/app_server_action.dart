import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 常驻的「服务器设置」入口。
///
/// **必须挂在框架层**（导航 / 页面脚手架），不能挂在页面内容里：服务端下线时
/// 页面内容往往整块渲染成错误态，挂在内容里的入口会跟着一起消失——而恰恰是
/// 这个时候用户最需要改地址。已登录又连不上服务器的场景曾因此完全无解。
class AppServerAction extends StatelessWidget {
  const AppServerAction({super.key, this.iconSize = 22});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 用 Obx 包一层：提示里带的是当前地址，改完要跟着变。
    return Obx(
      () => AppTooltip(
        message: '服务器设置（${ServerSettings.display}）',
        child: IconButton(
          icon: Icon(
            Icons.dns_outlined,
            size: iconSize,
            color: scheme.onSurfaceVariant,
          ),
          onPressed: () => ServerSettingsDialog.open<void>(),
        ),
      ),
    );
  }
}
