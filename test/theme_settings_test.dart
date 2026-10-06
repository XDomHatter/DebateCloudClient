import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/theme_settings.dart';
import 'package:flutter/material.dart';
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

  group('ThemeSettings', () {
    test('无持久化值时默认浅色', () async {
      await initCache();
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.light);
    });

    test('load 读回上次选择的深色', () async {
      await initCache(values: {'app.theme_mode': 'dark'});
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.dark);
    });

    test('load 读回浅色', () async {
      await initCache(values: {'app.theme_mode': 'light'});
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.light);
    });

    test('非法值回退浅色', () async {
      await initCache(values: {'app.theme_mode': 'xxx'});
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.light);
    });

    test('setMode 落盘深色，重新 load 保留选择', () async {
      await initCache();
      await ThemeSettings.load();

      await ThemeSettings.setMode(ThemeMode.dark);
      expect(ThemeSettings.mode.value, ThemeMode.dark);
      expect(Cache.p?.getString('app.theme_mode'), 'dark');

      // 模拟重启：清空内存态后重新读回。
      ThemeSettings.mode.value = ThemeMode.light;
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.dark);
    });

    test('setMode 落盘浅色，重新 load 保留选择', () async {
      await initCache(values: {'app.theme_mode': 'dark'});
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.dark);

      await ThemeSettings.setMode(ThemeMode.light);
      expect(Cache.p?.getString('app.theme_mode'), 'light');

      ThemeSettings.mode.value = ThemeMode.dark;
      await ThemeSettings.load();
      expect(ThemeSettings.mode.value, ThemeMode.light);
    });
  });
}
