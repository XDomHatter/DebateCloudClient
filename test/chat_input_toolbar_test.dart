// 回归测试：Markdown 工具条在输入区变窄时必须隐藏提示文字，而不是溢出。
//
// 根因：`_toolbar` 的 Row 是「5 个固定 32px 按钮 + Spacer + 不可压缩的 Text」。
// 宽度不够时 Spacer 先被压成 0，然后 Text 硬顶出右边界，报
// `A RenderFlex overflowed by 23 pixels on the right`。
//
// 输入区的宽度账（见 `_inputBar`）：
//   页面宽 − 32(padding) − 48(附件) − 8 − 12 − 48(发送) = 页面宽 − 148
// 所以下面直接用「输入区可用宽度」作为入参，不再减一次。
//
// 两个必须注意的点：
// 1. 必须用真实 AppTheme（裸 ThemeData 会漏掉主题相关的崩溃）；
// 2. flutter_test 的 defaultTargetPlatform 默认是 **Android**（环境里有
//    FLUTTER_TEST），而工具条文案按平台分叉，所以桌面用例必须显式 override，
//    且 override 要在 pumpWidget 之后立刻还原（放 tearDown 太晚）。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现用户报的桌面窄窗口：页面宽 367 → 输入区 219。
const double _narrowDesktop = 219;

/// Android 411dp（Pixel 常见宽度）→ 输入区 263。
const double _narrowAndroid = 263;

/// 宽到足够放下提示：输入区 450。
const double _wide = 450;

const String _desktopHint = 'Shift+Enter 换行';
const String _mobileHint = '支持 Markdown / LaTeX';

Widget _host(double inputWidth) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: inputWidth,
          child: ChatInputField(
            controller: TextEditingController(),
            onSubmitted: () {},
          ),
        ),
      ),
    ),
  );
}

/// 桌面端构建（pump 后立刻还原，避免污染后续用例）。
Future<void> _pumpDesktop(WidgetTester tester, double inputWidth) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  await tester.pumpWidget(_host(inputWidth));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('桌面宽（输入区 450）：提示显示，工具条不溢出', (tester) async {
    await _pumpDesktop(tester, _wide);

    expect(tester.takeException(), isNull);
    expect(find.text(_desktopHint), findsOneWidget);
    // 五个工具按钮一个都不能少。
    expect(find.byType(IconButton), findsNWidgets(5));
  });

  testWidgets('桌面窄（输入区 219）：提示隐藏，工具条不溢出', (tester) async {
    // 这正是用户报错的那档宽度：修复前这里会溢出 23px。
    await _pumpDesktop(tester, _narrowDesktop);

    expect(tester.takeException(), isNull);
    expect(find.text(_desktopHint), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(5));
  });

  testWidgets('Android 411dp（输入区 263）：提示隐藏，工具条不溢出', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_host(_narrowAndroid));
    debugDefaultTargetPlatformOverride = null;

    expect(tester.takeException(), isNull);
    expect(find.text(_mobileHint), findsNothing);
    expect(find.byType(IconButton), findsNWidgets(5));
  });

  testWidgets('Android 宽屏（输入区 450）：提示按移动端文案显示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_host(_wide));
    debugDefaultTargetPlatformOverride = null;

    expect(tester.takeException(), isNull);
    expect(find.text(_mobileHint), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(5));
  });
}
