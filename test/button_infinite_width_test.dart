// 回归测试：全站按钮主题的 minimumSize 用的是 Size.fromHeight，
// 其宽度为 double.infinity。Row 主轴不约束子项（maxWidth = Infinity），
// 于是按钮内部的 ConstrainedBox 会推出 w=Infinity 的紧约束，
// 触发 "BoxConstraints forces an infinite width"。
//
// 群聊信息页的「添加成员」按钮曾因此崩坏（group_info_view.dart:152）。
// 本文件锁定两种写法：裸按钮必须崩，显式有限 minimumSize 必须正常。
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻群聊信息页「成员」分区标题所在的约束环境：
/// ListView（高度无界）→ Center → ConstrainedBox(maxWidth) → Column → Row。
Widget _host(Widget button) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDesign.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('成员（3）'),
                      const Spacer(),
                      button,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('裸主题按钮在 Row 中会崩（问题复现）', (tester) async {
    await tester.pumpWidget(
      _host(
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('添加成员'),
        ),
      ),
    );
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('显式有限 minimumSize 后布局正常（修复验证）', (tester) async {
    await tester.pumpWidget(
      _host(
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('添加成员'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, AppDesign.controlHeight),
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceM),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('添加成员'), findsOneWidget);
  });
}
