// 金图：把「服务器设置」弹窗真的渲染出来。
//
// 自动化断言只能证明「有这个 widget」，证明不了它长得对不对（有没有溢出、
// 按钮挤不挤、中文是不是方块）。这张图让改动可目视复核。
//
// 生成：flutter test --update-goldens test/server_settings_dialog_golden_test.dart
import 'dart:io';

import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 测试默认字体 Ahem 会把字符画成方块，必须换成系统字体。
Future<void> _loadFont() async {
  final bytes = File('C:/Windows/Fonts/simhei.ttf').readAsBytesSync();
  final loader = FontLoader('GoldenFont')
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

void main() {
  testWidgets('golden: 服务器设置弹窗（浅色）', (tester) async {
    await _loadFont();

    // 必须用真实 AppTheme：按钮最小宽无穷大等约定都在这里，
    // 用裸 ThemeData 会漏掉布局问题。ThemeData.copyWith 没有 fontFamily，
    // 只能整体换 TextTheme。
    final base = AppTheme.light();
    final goldTextTheme = base.textTheme.apply(
      fontFamily: 'GoldenFont',
      fontFamilyFallback: const ['SimHei'],
    );

    // `ThemeData.copyWith(textTheme: ...)` 改不到按钮主题的 textStyle——
    // 它们捕获的是原始 typography 的 `labelLarge`，不是 theme.textTheme。
    // 只能挨个覆盖，让按钮文字也走带字体的版本。
    ButtonStyle copy(ButtonStyle? s) =>
        s?.copyWith(textStyle: WidgetStateProperty.all(goldTextTheme.labelLarge)) ?? s!;

    final theme = base.copyWith(
      textTheme: goldTextTheme,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: 'GoldenFont',
        fontFamilyFallback: const ['SimHei'],
      ),
      filledButtonTheme: FilledButtonThemeData(style: copy(base.filledButtonTheme.style)),
      textButtonTheme: TextButtonThemeData(style: copy(base.textButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: copy(base.outlinedButtonTheme.style)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: copy(base.elevatedButtonTheme.style)),
      // ListTile 的标题/副标题也用带字体的版本——SwitchListTile 同样吃这个。
      listTileTheme: base.listTileTheme.copyWith(
        titleTextStyle: goldTextTheme.titleSmall,
        subtitleTextStyle: goldTextTheme.bodySmall,
      ),
    );

    // 收窄画布：金图捕获的是整屏，默认 800×600 会让弹窗只占中间一小块，
    // 四周全是黑色遮罩，看不清细节。520×520 是常见的窄弹窗尺寸，
    // 还能同时验证短窗口下的布局紧凑度。
    tester.view.physicalSize = const Size(520, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      GetMaterialApp(
        theme: theme,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pump();

    Get.dialog<void>(const ServerSettingsDialog());
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/server_settings_dialog_light.png'),
    );
  });
}
