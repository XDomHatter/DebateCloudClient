import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

// Dart 字符串里 `$` 是插值符，测试里的公式一律用 `\$` 转义或 raw 字符串。
const _inlineTex = '\$x^2\$';

void main() {
  group('ChatMarkdown.prepare — 公式兜底', () {
    test('成对的行内公式原样保留', () {
      expect(ChatMarkdown.prepare('设 $_inlineTex 成立'), '设 $_inlineTex 成立');
    });

    test('未闭合的 \$ 转义为字面量，不会吞掉后面的正文', () {
      expect(ChatMarkdown.prepare('价格 \$100 元'), r'价格 \$100 元');
    });

    test('块级公式允许跨行', () {
      const src = '\$\$\nx = 1\n\$\$';
      expect(ChatMarkdown.prepare(src), src);
    });

    test('行内公式不允许跨行', () {
      expect(ChatMarkdown.prepare('\$x\n\$'), contains(r'\$'));
    });

    test('代码块与行内代码里的 \$ 完全不动', () {
      const inline = '`echo \$HOME`';
      expect(ChatMarkdown.prepare(inline), inline);
      const fence = '```\necho \$PATH\n```';
      expect(ChatMarkdown.prepare(fence), fence);
    });

    test('超长公式降级为普通文本', () {
      final body = 'a' * (ChatMarkdown.maxTexLength + 1);
      expect(ChatMarkdown.prepare('\$$body\$'), contains(r'\$'));
    });
  });

  group('ChatMarkdown.strip — 摘要纯文本化', () {
    test('标题与强调', () {
      expect(ChatMarkdown.strip('## 标题\n**粗体**'), '标题 粗体');
    });

    test('链接只留文字', () {
      expect(ChatMarkdown.strip('见 [文档](https://a.com) 说明'), '见 文档 说明');
    });

    test('图片留 alt，无 alt 时给占位', () {
      expect(ChatMarkdown.strip('![封面](https://a.com/x.png)'), '封面');
      expect(ChatMarkdown.strip('![](https://a.com/x.png)'), '[图片]');
    });

    test('公式去掉定界符、保留内容', () {
      expect(ChatMarkdown.strip('公式 $_inlineTex 结束'), '公式 x^2 结束');
    });

    test('代码块整段丢弃', () {
      expect(ChatMarkdown.strip('前\n```\ncode\n```\n后'), '前 后');
    });

    test('表格分隔行不出现在摘要里', () {
      expect(
        ChatMarkdown.strip('| a | b |\n|---|---|\n| 1 | 2 |'),
        'a b 1 2',
      );
    });

    test('普通文本原样返回', () {
      expect(ChatMarkdown.strip('明天下午三点开会'), '明天下午三点开会');
    });
  });

  group('ChatMarkdown.looksRich — 解析短路', () {
    test('纯文本不进渲染路径', () {
      expect(ChatMarkdown.looksRich('你好，明天见'), isFalse);
    });

    test('带 Markdown 标记才进渲染路径', () {
      expect(ChatMarkdown.looksRich('**重点**'), isTrue);
      expect(ChatMarkdown.looksRich('- 第一点\n- 第二点'), isTrue);
      expect(ChatMarkdown.looksRich(_inlineTex), isTrue);
    });
  });

  group('ChatRichText', () {
    testWidgets('开关关闭时按纯文本渲染', (tester) async {
      ChatSettings.richTextEnabled.value = false;
      addTearDown(() => ChatSettings.richTextEnabled.value = true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatRichText('**粗体** 与 $_inlineTex')),
        ),
      );
      expect(find.text('**粗体** 与 $_inlineTex'), findsOneWidget);
      expect(find.byType(GptMarkdown), findsNothing);
    });

    testWidgets('开关打开时走 Markdown 渲染', (tester) async {
      ChatSettings.richTextEnabled.value = true;

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ChatRichText('**粗体**'))),
      );
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('enabled=false 强制纯文本', (tester) async {
      ChatSettings.richTextEnabled.value = true;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChatRichText('**粗体**', enabled: false)),
        ),
      );
      expect(find.text('**粗体**'), findsOneWidget);
    });

    testWidgets('超长富文本默认折叠，点击展开后变收起', (tester) async {
      ChatSettings.richTextEnabled.value = true;
      // 触发折叠阈值（600）+ 富文本特征；用 `b` 填充是因为它不属于富文本标记，
      // 避免改写为合法 Markdown 后被解析成意外结构。
      final long = '**长消息**\n\n' + 'b' * 700; // ignore: prefer_interpolation_to_compose_strings
      // 真实聊天场景里 ChatRichText 出现在 ListView item，没有 maxHeight 约束。
      // 这里用 SingleChildScrollView 模拟：让 GptMarkdown 在无界高度下 layout，
      // 避免测试默认 800x600 窗口触发 RenderFlex overflow 误报。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SingleChildScrollView(child: ChatRichText(long)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('展开'), findsOneWidget);
      expect(find.text('收起'), findsNothing);

      await tester.tap(find.text('展开'));
      await tester.pumpAndSettle();
      expect(find.text('收起'), findsOneWidget);
      expect(find.text('展开'), findsNothing);
    });

    testWidgets('AppTheme 下渲染代码块不触发无限宽约束', (tester) async {
      // 回归用例：AppTheme 把按钮 minimumSize 设为 Size.fromHeight(48)
      //（最小宽无穷大），而 gpt_markdown 代码块的复制按钮是 Row 里的
      // TextButton.icon——Row 对非 flex 子不施加宽度约束，两者叠加会抛
      // "BoxConstraints forces an infinite width"。ChatRichText 必须在自己的
      // 子树内把按钮最小尺寸压成有界值。
      ChatSettings.richTextEnabled.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ChatRichText('```dart\nfinal x = 1;\n```'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(GptMarkdown), findsOneWidget);
    });

    testWidgets('短消息不出现展开按钮', (tester) async {
      ChatSettings.richTextEnabled.value = true;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ChatRichText('**短**'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('展开'), findsNothing);
      expect(find.text('收起'), findsNothing);
    });
  });

  group('缓存', () {
    setUp(ChatMarkdown.debugClearCaches);

    test('prepare 同输入返回字符串驻留（命中 LRU）', () {
      final a = ChatMarkdown.prepare(r'价格 \$100');
      final b = ChatMarkdown.prepare(r'价格 \$100');
      expect(b, a);
      expect(identical(a, b), isTrue);
    });

    test('strip 同输入也走缓存', () {
      final a = ChatMarkdown.strip('**重点** 文字');
      final b = ChatMarkdown.strip('**重点** 文字');
      expect(identical(a, b), isTrue);
    });
  });
}
