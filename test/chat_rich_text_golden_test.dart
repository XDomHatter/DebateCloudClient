import 'dart:io';

import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用 raw 字符串写样例：LaTeX 用 `\(` `\)` `\[` `\]`，避开 Dart 的 `$` 插值。
const _sample = r'''
**粗体 Bold**、*斜体*、行内 `code`，行内公式 \(E = mc^2\)。

块级公式：

\[
\int_0^1 x^2\,dx = \frac{1}{3}
\]

```dart
final growth = currentRevenue * 1.18;
```

| 项目 | 数值 |
|:---|---:|
| Q1 | 120 |
| Q2 | 142 |

- 列表项一
- 列表项二
''';

Future<void> _loadLatinFont() async {
  // 测试默认字体 Ahem 会把所有拉丁字母画成方块，加载系统字体才能看清排版。
  const candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    'C:/Windows/Fonts/arial.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader('LatinTestFont')
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    await loader.load();
    return;
  }
}

void main() {
  testWidgets('golden: Markdown + LaTeX 气泡（暗色）', (tester) async {
    await _loadLatinFont();
    ChatSettings.richTextEnabled.value = true;

    const textStyle = TextStyle(
      fontFamily: 'LatinTestFont',
      fontSize: 14,
      color: Colors.white,
    );

    await tester.pumpWidget(
      MaterialApp(
// 复用真实 AppTheme 的按钮主题（含「按钮最小宽无穷大」的约定）才能覆盖到
        // 代码块复制按钮那条渲染路径——用裸 ThemeData 会漏掉这个 bug。
        // 字体仍换成系统拉丁字体，避免 Ahem 把字母画成方块看不清排版。
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          fontFamily: 'LatinTestFont',
          textButtonTheme: AppTheme.dark().textButtonTheme,
          elevatedButtonTheme: AppTheme.dark().elevatedButtonTheme,
          filledButtonTheme: AppTheme.dark().filledButtonTheme,
          outlinedButtonTheme: AppTheme.dark().outlinedButtonTheme,
        ),
        home: Scaffold(
          body: Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1E293B),
              child: const ChatRichText(_sample, style: textStyle),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChatRichText),
      matchesGoldenFile('goldens/chat_rich_text_dark.png'),
    );
  });
}
