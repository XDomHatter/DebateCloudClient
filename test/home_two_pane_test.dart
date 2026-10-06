// 回归测试：赛事中心在宽屏下走「左列表 + 右预览」双栏，窄屏退回网格。
//
// 双栏的门槛是**可用宽度** [AppDesign.bpTwoPane]（1000），不是窗口宽度：
// 真机上还要先扣掉侧边导航（220）与内边距（32），所以 1024 的窗口并不触发。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/models/home/controller.dart';
import 'package:debate_cloud/models/home/view.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

Competition _comp(int id) => Competition(
  id: id,
  name: '赛事 $id',
  description: '这是赛事 $id 的简介',
  jsonDes: '',
  startDate: DateTime(2026, 10, 1),
  endDate: DateTime(2026, 10, 3),
  signupStartDate: DateTime(2026, 9, 1),
  signupEndDate: DateTime(2026, 9, 25),
);

Future<void> _pumpWith(
  WidgetTester tester,
  double width,
  List<Competition> comps,
) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    // HomeView 的构造函数会 Get.put(HomeController())，不能是 const。
    MaterialApp(theme: AppTheme.light(), home: HomeView()),
  );
  // 数据直接塞进控制器：绕过真实网络，只验证版式分支。
  final c = Get.find<HomeController>();
  c.competitions.value = comps;
  c.isLoading.value = false;
  await tester.pump();
}

void main() {
  setUp(() {
    // 骨架屏的 AnimationController 会挂住定时器，测试里必须关掉。
    AppSkeleton.animate = false;
  });

  tearDown(Get.reset);

  testWidgets('可用宽 ≥ 1000：左列表 + 右预览', (tester) async {
    await _pumpWith(tester, 1200, [_comp(1), _comp(2), _comp(3)]);

    expect(tester.takeException(), isNull);
    // 右侧预览的 CTA 是双栏独有标记。
    expect(find.text('查看详情'), findsOneWidget);
    // 三条都在左栏里。
    expect(find.text('赛事 1'), findsWidgets);
    expect(find.text('赛事 3'), findsWidgets);
    // 默认预览第一条：左栏卡片里一份 + 右栏预览里一份。
    expect(find.text('这是赛事 1 的简介'), findsNWidgets(2));
  });

  testWidgets('可用宽 < 1000：退回单栏网格，没有预览', (tester) async {
    await _pumpWith(tester, 900, [_comp(1), _comp(2)]);

    expect(tester.takeException(), isNull);
    expect(find.text('查看详情'), findsNothing);
    expect(find.text('赛事 1'), findsWidgets);
  });

  testWidgets('双栏下点列表项切换右侧预览', (tester) async {
    await _pumpWith(tester, 1200, [_comp(1), _comp(2)]);

    await tester.tap(find.text('赛事 2'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('这是赛事 2 的简介'), findsNWidgets(2));
    // 赛事 1 只剩下左栏卡片里那份，不再是预览。
    expect(find.text('这是赛事 1 的简介'), findsOneWidget);
  });
}
