import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'cache.dart';

/// 应用主题偏好，落盘到 SharedPreferences（见 [Cache.p]）。
///
/// 仅提供浅色 / 深色两个选项，不跟随系统：默认浅色，用户手动切换后
/// 记住选择，重启后保留。
abstract final class ThemeSettings {
  static const String _keyMode = 'app.theme_mode';

  /// 当前主题模式。默认浅色。
  static final Rx<ThemeMode> mode = ThemeMode.light.obs;

  /// 在 [Cache.init] 之后调用，读回上次的选择。
  static Future<void> load() async {
    final p = Cache.p;
    if (p == null) return;
    mode.value = _parse(p.getString(_keyMode));
  }

  /// 切换主题并落盘。切换即时生效（见 main.dart 的 Obx 绑定）。
  static Future<void> setMode(ThemeMode value) async {
    mode.value = value;
    await Cache.p?.setString(
      _keyMode,
      switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        // 没有跟随系统选项，system 视为默认浅色。
        ThemeMode.system => 'light',
      },
    );
  }

  static ThemeMode _parse(String? raw) => switch (raw) {
    'dark' => ThemeMode.dark,
    _ => ThemeMode.light,
  };
}
