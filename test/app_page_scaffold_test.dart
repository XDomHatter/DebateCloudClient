// 回归测试：AppPageScaffold 的四件事（AppBar / 居中限宽 / 下拉刷新 / 加载态）
// 与侧边导航的展开门槛。
//
// AppPageScaffold 收编了十几个页面里重复的
// `Scaffold + RefreshIndicator + ListView + Align + ConstrainedBox` 样板，
// 这里把它的契约钉住：改行为必须改测试。
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _probe = Key('probe');

Widget _host(Widget page) {
  return MaterialApp(theme: AppTheme.light(), home: page);
}

void main() {
  testWidgets('给了 title 就生成 AppBar', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppPageScaffold(
          title: '测试页',
          children: [Text('内容')],
        ),
      ),
    );

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('测试页'), findsOneWidget);
  });

  testWidgets('children 会被限宽：宽屏不超过 maxWidth', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const AppPageScaffold(
          maxWidth: 400,
          children: [SizedBox(key: _probe, width: double.infinity, height: 20)],
        ),
      ),
    );

    // 屏幕 1200，限宽 400 → 内容块就是 400，不会被拉成 1168。
    // 注：padding 是 ListView 的 padding，作用在滚动视口上，不在这里再减一次。
    expect(tester.getSize(find.byKey(_probe)).width, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('children 在窄屏上让位给 padding', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const AppPageScaffold(
          children: [SizedBox(key: _probe, width: double.infinity, height: 20)],
        ),
      ),
    );

    // 屏幕 360 → 视口 360 - 16×2 = 328。
    expect(tester.getSize(find.byKey(_probe)).width, 328);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loadingState 优先于主体内容', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppPageScaffold(
          title: '测试页',
          loadingState: Text('加载中'),
          children: [Text('内容')],
        ),
      ),
    );

    expect(find.text('加载中'), findsOneWidget);
    expect(find.text('内容'), findsNothing);
  });

  testWidgets('给了 onRefresh 才包 RefreshIndicator', (tester) async {
    await tester.pumpWidget(
      _host(AppPageScaffold(children: const [Text('内容')])),
    );
    expect(find.byType(RefreshIndicator), findsNothing);

    await tester.pumpWidget(
      _host(
        AppPageScaffold(
          onRefresh: () async {},
          children: const [Text('内容')],
        ),
      ),
    );
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('header 固定在滚动区上方，两者同时可见', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppPageScaffold(
          header: Text('固定头部'),
          children: [Text('滚动内容')],
        ),
      ),
    );

    expect(find.text('固定头部'), findsOneWidget);
    expect(find.text('滚动内容'), findsOneWidget);

    final header = tester.getTopLeft(find.text('固定头部'));
    final body = tester.getTopLeft(find.text('滚动内容'));
    // 头部在滚动区之上：纵向顺序不能颠倒。
    expect(header.dy, lessThan(body.dy));
  });

  testWidgets('侧边导航只在桌面宽度允许展开', (tester) async {
    expect(MainNavRail.canExtendAt(1023), isFalse);
    expect(MainNavRail.canExtendAt(1024), isTrue);
    expect(AppDesign.railWidth, lessThan(AppDesign.railWidthExtended));
  });
}
