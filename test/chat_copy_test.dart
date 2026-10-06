// 聊天复制功能的回归测试。
//
// 覆盖三件事：
// 1) 复制内容 —— 必须是服务端下发的 `content` **原文**，不能是
//    `ChatMarkdown.prepare()` 的输出（prepare 会把未配对的 `$` 转义成 `\$`）；
//    「复制纯文本」则必须等于 `ChatMarkdown.strip` 的结果。
// 2) 触发路径 —— 长按弹底部菜单、桌面端右键弹上下文菜单、桌面端悬停角标，
//    三条路径都要落到同一个复制入口。
// 3) 折叠态 —— 超 600 字的消息默认折叠、不挂载 GptMarkdown，
//    此时复制到的仍必须是完整原文（这正是「整条复制原文」相对「选区复制」的优势）。
//
// 必须使用真实 AppTheme：裸 ThemeData 会漏掉项目按钮主题相关的崩溃
// （按钮主题 minimumSize 宽度为无穷大，裸放进 Row 会直接崩）。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:debate_cloud/widgets/chat_clipboard.dart';
import 'package:debate_cloud/widgets/chat_rich_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 最近一次写进剪贴板的文本。
String? clipboardText;

/// 捕获到的剪贴板写入次数，用来验证「空内容不写剪贴板」。
int clipboardWrites = 0;

/// 捕获到的提示文案（label, message）。
List<(String, String)> toasts = [];

Future<Object?> _platformHandler(MethodCall call) async {
  if (call.method == 'Clipboard.setData') {
    clipboardWrites += 1;
    clipboardText = (call.arguments as Map)['text'] as String?;
  }
  return null;
}

/// 用带真实主题的壳挂载被测组件。
///
/// 用 GetMaterialApp 而非裸 MaterialApp：`ChatRichText` 内部是 `Obx`，
/// 折叠/富文本分支需要 Get 的上下文。
Future<void> pumpShell(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    GetMaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, child: child)),
      ),
    ),
  );
}

/// 一个可见、可命中的假气泡。
Widget fakeBubble({Color color = const Color(0xFFE0E0E0)}) => Container(
      height: 48,
      color: color,
      alignment: Alignment.center,
      child: const Text('气泡'),
    );

void main() {
  setUp(() {
    Get.testMode = true;
    clipboardText = null;
    clipboardWrites = 0;
    toasts = [];
    // 让测试只关心「复制了什么」，不必背负 snackbar 的挂载与定时器。
    ChatCopy.debugToastOverride = (label, message) => toasts.add((label, message));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, _platformHandler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    ChatCopy.debugToastOverride = null;
    ChatMarkdown.debugClearCaches();
  });

  group('ChatCopy — 复制内容', () {
    testWidgets('复制原文：写入 content 原文，且不经过 prepare 转义', (tester) async {
      await pumpShell(tester, const SizedBox.shrink());

      // 未配对的 `$100` 是 prepare 的敏感点：prepare 会把它改成 `\$100`。
      const raw = r'价格 $100，公式 $x^2$，**粗体**，表格 |a|b|';
      await ChatCopy.raw(raw);

      expect(clipboardText, raw, reason: '必须是原文，一个字符都不能变');
      expect(clipboardText, isNot(contains(r'\$')));
      expect(toasts.single.$1, '已复制原文');
    });

    testWidgets('复制纯文本：等于 ChatMarkdown.strip 的结果', (tester) async {
      await pumpShell(tester, const SizedBox.shrink());

      const raw = '**粗体** 与 \$x^2\$\n\n- 列表项一\n- 列表项二';
      await ChatCopy.plain(raw);

      expect(clipboardText, ChatMarkdown.strip(raw));
      expect(clipboardText, isNot(contains('**')));
      expect(toasts.single.$1, '已复制纯文本');
    });

    testWidgets('空白内容不写剪贴板，也不弹提示', (tester) async {
      await pumpShell(tester, const SizedBox.shrink());

      await ChatCopy.raw('   \n  ');

      expect(clipboardWrites, 0);
      expect(toasts, isEmpty);
    });

    testWidgets('提示里的预览被压成单行并截断', (tester) async {
      await pumpShell(tester, const SizedBox.shrink());

      await ChatCopy.raw('第一行\n第二行');

      expect(toasts.single.$2, '第一行 第二行');
    });
  });

  group('ChatCopyWrapper — 触发路径', () {
    testWidgets('长按气泡：弹菜单，选「复制原文」写入原文', (tester) async {
      const raw = '**加粗** 与 \$E=mc^2\$';
      await pumpShell(
        tester,
        ChatCopyWrapper(content: raw, child: fakeBubble()),
      );

      await tester.longPress(find.byType(ChatCopyWrapper));
      await tester.pumpAndSettle();

      expect(find.text('复制原文'), findsOneWidget);
      expect(find.text('复制纯文本'), findsOneWidget);

      await tester.tap(find.text('复制原文'));
      await tester.pumpAndSettle();

      expect(clipboardText, raw);
    });

    testWidgets('长按气泡：选「复制纯文本」写入去标记结果', (tester) async {
      const raw = '**加粗** 与 \$E=mc^2\$';
      await pumpShell(
        tester,
        ChatCopyWrapper(content: raw, child: fakeBubble()),
      );

      await tester.longPress(find.byType(ChatCopyWrapper));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制纯文本'));
      await tester.pumpAndSettle();

      expect(clipboardText, ChatMarkdown.strip(raw));
    });

    testWidgets('桌面端右键：弹上下文菜单，选「复制原文」写入原文', (tester) async {
      const raw = r'# 标题' '\n正文 \$a+b\$';
      await pumpShell(
        tester,
        ChatCopyWrapper(content: raw, child: fakeBubble()),
      );

      await tester.tap(
        find.byType(ChatCopyWrapper),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('复制原文'), findsOneWidget);
      await tester.tap(find.text('复制原文'));
      await tester.pumpAndSettle();

      expect(clipboardText, raw);
    });

    testWidgets('桌面端悬停：出现复制角标，点击即复制原文', (tester) async {
      // debugDefaultTargetPlatformOverride 必须在**测试体内**还原：
      // TestWidgetsFlutterBinding._verifyInvariants 在测试体结束时就检查，
      // 放 tearDown 太晚，会报「foundation debug variable was changed by the test」。
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        const raw = '悬停复制的原文 \$x^2\$';
        await pumpShell(
          tester,
          ChatCopyWrapper(content: raw, child: fakeBubble()),
        );

        // 未悬停时不显示角标。
        expect(find.byIcon(Icons.content_copy_outlined), findsNothing);

        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byType(ChatCopyWrapper)));
        await tester.pump();

        expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);

        await tester.tap(find.byIcon(Icons.content_copy_outlined));
        await tester.pump();

        expect(clipboardText, raw);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('移动端不挂悬停角标（无悬停概念）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpShell(
          tester,
          ChatCopyWrapper(content: '移动端消息', child: fakeBubble()),
        );
        expect(find.byIcon(Icons.content_copy_outlined), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('折叠态与长消息', () {
    testWidgets('超 600 字折叠态：复制到的是完整原文', (tester) async {
      ChatSettings.richTextEnabled.value = true;
      // 折叠阈值 600，这里造一条远超阈值的富文本消息。
      final raw = '# 长论证\n${'**粗体** 内容 \$x^2\$ 句子。' * 60}';
      expect(raw.length, greaterThan(600));
      expect(ChatMarkdown.looksRich(raw), isTrue);

      await pumpShell(
        tester,
        ChatCopyWrapper(content: raw, child: ChatRichText(raw)),
      );

      // 折叠态：不挂 GptMarkdown，只显示一行提示。
      expect(find.textContaining('消息较长'), findsOneWidget);

      await tester.longPress(find.byType(ChatCopyWrapper));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制原文'));
      await tester.pumpAndSettle();

      expect(clipboardText, raw, reason: '折叠只影响展示，不影响复制内容');
      expect(clipboardText!.length, greaterThan(600));
    });

    testWidgets('气泡内不引入无限宽约束（回归按钮主题的 minimumSize）', (tester) async {
      // 悬停角标是自绘 Container，不是 TextButton/IconButton，
      // 因此不会踩到「按钮主题 minimumSize 宽度无穷大」那条坑。
      // 这条用例保证以后有人把它换成裸按钮时会立刻失败。
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await pumpShell(
          tester,
          ChatCopyWrapper(content: '内容', child: fakeBubble()),
        );
        final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byType(ChatCopyWrapper)));
        await tester.pump();

        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
