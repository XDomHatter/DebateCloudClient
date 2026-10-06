// 回归测试：服务端下线时，「服务器设置」仍然够得着。
//
// 曾出的真实问题：入口挂在页面内容里（登录页齿轮 / 个人页卡片）。已登录又连
// 不上服务器时，登录页不可达，而个人页、赛事中心整块渲染成错误态——入口跟着
// 一起消失，用户完全无法改地址。修法是把入口挪到框架层：页面脚手架 + 导航。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/routed_apps/chat/contacts_view.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('页面脚手架默认带服务器入口，点击能打开弹窗', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: const AppPageScaffold(
          title: '测试页',
          children: [Text('内容')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dns_outlined));
    await tester.pumpAndSettle();

    expect(find.text('服务器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showServerAction 为 false 时不挂入口', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: const AppPageScaffold(
          title: '测试页',
          showServerAction: false,
          children: [Text('内容')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dns_outlined), findsNothing);
  });

  testWidgets('页面处于加载态 / 错误态时入口依然在', (tester) async {
    // 错误态下内容区是 AppEmptyState，但脚手架（含 AppBar）照常渲染，
    // 这正是入口必须挂在脚手架上而不是内容里的原因。
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: const AppPageScaffold(
          title: '测试页',
          children: [Text('加载失败')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
  });

  testWidgets('导航 rail 的服务器入口会触发回调', (tester) async {
    var opened = false;

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 168,
            child: MainNavRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              onOpenChatSubPage: (_) {},
              onOpenServerSettings: () => opened = true,
              extended: true,
              canExtend: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('服务器'), findsOneWidget);
    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('提示里带当前地址，改完会跟着变', (tester) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: const AppPageScaffold(
          title: '测试页',
          children: [Text('内容')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(ServerSettings.display, '${ServerSettings.host.value}:${ServerSettings.port.value}');
    await ServerSettings.set(host: '10.0.0.5', port: 9000, https: false);
    await tester.pump();
    expect(ServerSettings.display, '10.0.0.5:9000');
  });

  // 防止导航改动影响二级入口的既有行为。
  testWidgets('二级入口照常工作', (tester) async {
    Widget? opened;

    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 168,
            child: MainNavRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              onOpenChatSubPage: (page) => opened = page,
              extended: true,
              canExtend: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('通讯录'));
    await tester.pumpAndSettle();

    expect(opened, isA<ContactsPage>());
  });
}
