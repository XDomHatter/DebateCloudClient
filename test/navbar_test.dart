// 回归测试：侧边导航 MainNavRail 的两种形态（收起 / 展开）与点击回调。
//
// MainNavRail 之前必须拿到 MainNavController，而后者在构造期就 Get.find 了
// MainScaffoldController（连带 HomeView 及其网络请求），导致导航没法单独
// 做 widget 测试。改成纯展示组件后，这里才能把「扁平化」的契约钉住：
// 展开宽度 168、一二级共用同一行高、收起态不画文字。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/routed_apps/chat/contacts_view.dart';
import 'package:debate_cloud/widgets/navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _rail = Key('rail');

Widget _host(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: child);
}

Widget _railOf({
  int selectedIndex = 0,
  void Function(int)? onDestinationSelected,
  void Function(Widget page)? onOpenChatSubPage,
  bool extended = false,
  bool canExtend = false,
  VoidCallback? onToggleExtended,
}) {
  return _host(
    SizedBox(
      width: 1200,
      height: 800,
      child: Row(
        children: [
          MainNavRail(
            key: _rail,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected ?? (_) {},
            onOpenChatSubPage: onOpenChatSubPage ?? (_) {},
            extended: extended,
            canExtend: canExtend,
            onToggleExtended: onToggleExtended,
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('收起态：宽度 72，图标按钮是 40×40 且不拉长', (tester) async {
    await tester.pumpWidget(_railOf(canExtend: true, extended: false));

    // 钉字面值而不是 AppDesign 常量：常量改了测试还绿，就挡不住回退。
    expect(tester.getSize(find.byKey(_rail)).width, 72);
    expect(find.text('赛事'), findsNothing);
    expect(find.text('通讯录'), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsNothing); // 选中态用 home
    expect(find.byIcon(Icons.home), findsOneWidget);

    // 收起态必须是正方形图标按钮；通栏的话这里会是 56×40，
    // 一个 20px 图标浮在中间，看着就是被拉长的横条。
    expect(tester.getSize(find.byType(InkWell).first), const Size(40, 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('收起态：图标、Logo、展开按钮三者同心', (tester) async {
    await tester.pumpWidget(_railOf(canExtend: true, extended: false));

    // 栏宽 72 → 中线 x=36。
    expect(tester.getCenter(find.byIcon(Icons.home)).dx, 36);
    expect(tester.getCenter(find.byIcon(Icons.forum_outlined)).dx, 36);
    expect(tester.getCenter(find.byIcon(Icons.chevron_right)).dx, 36);
  });

  testWidgets('展开态：宽度 168，主入口与二级入口都出现', (tester) async {
    await tester.pumpWidget(_railOf(canExtend: true, extended: true));

    // 同上，钉字面值 168。
    expect(tester.getSize(find.byKey(_rail)).width, 168);
    for (final label in ['赛事', '消息', '我的']) {
      expect(find.text(label), findsOneWidget, reason: '$label 应可见');
    }
    for (final label in ['通讯录', '好友申请', '通知']) {
      expect(find.text(label), findsOneWidget, reason: '$label 应可见');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('点一级入口回调对应索引', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _railOf(
        canExtend: true,
        extended: true,
        onDestinationSelected: picked.add,
      ),
    );

    await tester.tap(find.text('消息'));
    await tester.pump();
    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(picked, [1, 2]);
  });

  testWidgets('点二级入口打开对应页面', (tester) async {
    final opened = <Widget>[];
    await tester.pumpWidget(
      _railOf(
        canExtend: true,
        extended: true,
        onOpenChatSubPage: opened.add,
      ),
    );

    await tester.tap(find.text('通讯录'));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single, isA<ContactsPage>());
  });

  testWidgets('展开态有收起按钮且能触发；不允许展开时没有按钮', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      _railOf(
        canExtend: true,
        extended: true,
        onToggleExtended: () => toggled++,
      ),
    );

    // 展开态对齐图标槽（8 内边距 + 12 间距 + 图标半宽），不是栏中线。
    expect(tester.getCenter(find.byIcon(Icons.home)).dx, 30);
    expect(tester.getCenter(find.byIcon(Icons.chevron_left)).dx, 30);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(toggled, 1);

    // 600–1023 这一档永远收起，不给展开按钮（点了也没用）。
    await tester.pumpWidget(_railOf(canExtend: false, extended: true));
    // 宽度是 AnimatedContainer，得等动画走完再量。
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(tester.getSize(find.byKey(_rail)).width, 72);
  });

  testWidgets('收起态点击不报错（tooltip 不吞 tap）', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _railOf(
        canExtend: true,
        extended: false,
        onDestinationSelected: picked.add,
      ),
    );

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pump();

    expect(picked, [1]);
    expect(tester.takeException(), isNull);
  });
}
