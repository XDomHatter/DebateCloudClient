// 回归测试：聊天页发送消息后，焦点必须留在输入框。
//
// 桌面端（Windows / Linux / macOS）存在两条框架级失焦路径：
// 1) Enter 提交 —— EditableText.performAction 对 TextInputAction.send 走
//    _finalizeEditing(action, shouldUnfocus: true)，只要 onEditingComplete 为 null
//    就会调用 focusNode.unfocus()；
// 2) 点击输入框之外 —— EditableText 的 onTapOutside 默认动作
//    _EditableTextTapOutsideAction 在桌面端无条件 unfocus()。发送按钮与
//    Markdown 工具条都落在输入框之外。
//
// 修复手段（chat_widgets.dart）：
// - ChatInputField 传非空 onEditingComplete，阻断路径 1；
// - 输入框、发送按钮、工具条共用 chatInputTapGroupId，被 TextFieldTapRegion
//   视作同一区域，阻断路径 2。
//
// 注意：发送按钮位于页面（chat_detail_view.dart / group_chat_view.dart 的
// _inputBar），不在 ChatInputField 内部，所以这里复刻两页的 _inputBar 结构。
// 必须使用真实 AppTheme —— 裸 ThemeData 会漏掉项目按钮主题相关的崩溃。
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻聊天页底部输入栏：ChatInputField + 分组后的发送按钮。
class _InputBarHarness extends StatelessWidget {
  const _InputBarHarness({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.restoreFocus = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  /// 是否启用「提交后抢回焦点」兜底。
  /// 置 false 可隔离验证框架侧修复（onEditingComplete / TapRegion 分组）本身是否生效。
  final bool restoreFocus;

  void _submit() {
    onSubmit();
    controller.clear();
    if (restoreFocus) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesign.spaceM,
                vertical: AppDesign.spaceS,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ChatInputField(
                      controller: controller,
                      focusNode: focusNode,
                      onSubmitted: _submit,
                    ),
                  ),
                  const SizedBox(width: AppDesign.spaceS),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty;
                      return TextFieldTapRegion(
                        groupId: chatInputTapGroupId,
                        child: IconButton.filled(
                          tooltip: '发送',
                          onPressed: canSend ? _submit : null,
                          icon: const Icon(Icons.send),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 在「桌面端」平台下执行 [body]。
///
/// ChatInputField 只在桌面端接 onSubmitted 并把 action 设为 send，
/// 不覆盖平台就覆盖不到真实路径。
///
/// 注意：`debugDefaultTargetPlatformOverride` 必须在**测试体结束前**还原，
/// 否则 TestWidgetsFlutterBinding._verifyInvariants 会以
/// "The value of a foundation debug variable was changed by the test" 直接判失败，
/// 所以不能放在 setUp / tearDown 里。
Future<void> asDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late List<String> sent;

  Future<void> pumpHarness(
    WidgetTester tester, {
    bool restoreFocus = true,
  }) async {
    controller = TextEditingController();
    focusNode = FocusNode();
    sent = <String>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _InputBarHarness(
        controller: controller,
        focusNode: focusNode,
        restoreFocus: restoreFocus,
        onSubmit: () => sent.add(controller.text),
      ),
    );
  }

  testWidgets('桌面端 Enter 提交后焦点仍在输入框', (tester) async {
    await asDesktop(() async {
      await pumpHarness(tester);
      await tester.enterText(find.byType(TextField), '你好');
      expect(focusNode.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(sent, ['你好'], reason: 'Enter 必须触发提交');
      expect(controller.text, isEmpty, reason: '提交后应清空输入框');
      expect(focusNode.hasFocus, isTrue, reason: 'Enter 发送后必须保留焦点');
    });
  });

  testWidgets('Enter 失焦由 onEditingComplete 阻断（不依赖兜底 requestFocus）',
      (tester) async {
    await asDesktop(() async {
      await pumpHarness(tester, restoreFocus: false);
      await tester.enterText(find.byType(TextField), '你好');

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(sent, ['你好']);
      expect(
        focusNode.hasFocus,
        isTrue,
        reason: 'onEditingComplete 必须阻断 _finalizeEditing 的 focusNode.unfocus()',
      );
    });
  });

  testWidgets('点击发送按钮后焦点仍在输入框', (tester) async {
    await asDesktop(() async {
      await pumpHarness(tester);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(sent, ['hi']);
      expect(focusNode.hasFocus, isTrue, reason: '点击发送按钮后必须保留焦点');
    });
  });

  testWidgets('点击 Markdown 工具条后焦点仍在输入框', (tester) async {
    await asDesktop(() async {
      await pumpHarness(tester);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();

      // 工具条没有 requestFocus 兜底，这条能直接暴露 onTapOutside 失焦。
      //
      // 按图标找而不是 `find.byTooltip('加粗')`：悬停提示已换成自绘的
      // `AppTooltip`（规避 Windows 的 AXTree 引擎 Bug），它不再是 material
      // 的 `Tooltip`，`byTooltip` 找不到。
      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue, reason: '工具条属于输入区，点击不应失焦');
    });
  });

  testWidgets('点击输入区之外仍然正常失焦（非全局屏蔽）', (tester) async {
    await asDesktop(() async {
      await pumpHarness(tester);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();

      await tester.tapAt(const Offset(200, 100));
      await tester.pumpAndSettle();

      expect(
        focusNode.hasFocus,
        isFalse,
        reason: '输入区外的点击应保持桌面端默认失焦行为',
      );
    });
  });
}
