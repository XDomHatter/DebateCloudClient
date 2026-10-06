// 回归测试：P0/P1 新增的通用组件（AppInfoCard / AppPanel / AppSkeleton /
// AppEmptyState 两级文案）在真实主题下不溢出、不抛异常。
//
// 用真实 AppTheme 的原因同 button_infinite_width_test：裸 ThemeData 会漏掉
// 主题里的尺寸 / 颜色配置引发的崩溃。
//
// flutter_test 默认字体每字符占满 em 方框，宽度 ≈ 字符数 × 字号，这里的
// 文本长度都刻意写长，用来逼出溢出。
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool dark = false}) {
  return MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 340, height: 640, child: child),
      ),
    ),
  );
}

void main() {
  group('AppInfoCard', () {
    for (final dark in [false, true]) {
      testWidgets('${dark ? '深色' : '浅色'}：标题 + 描述 + 状态 + 元信息不溢出',
          (tester) async {
        await tester.pumpWidget(
          _host(
            AppInfoCard(
              large: true,
              title: '一个非常非常长的赛事名称用来测试省略号是否正确生效',
              status: AppStatus.success,
              statusLabel: '报名中',
              description:
                  '赛事简介同样故意写得非常长，用来验证描述区域最多两行且不会把卡片撑破。',
              meta: const [
                AppMetaRow(
                  icon: Icons.event_outlined,
                  label: '比赛',
                  value: '2026-01-01 ~ 2026-12-31',
                ),
                AppMetaRow(
                  icon: Icons.how_to_reg_outlined,
                  label: '报名',
                  value: '2026-01-01 ~ 2026-12-31',
                ),
              ],
            ),
            dark: dark,
          ),
        );

        expect(tester.takeException(), isNull);
        // 标题必须限制为单行省略：固定高度的网格（赛事中心 168）容不下两行。
        final title = tester.widget<Text>(
          find.text('一个非常非常长的赛事名称用来测试省略号是否正确生效'),
        );
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
      });
    }

    testWidgets('chips 为空数组时不留空行', (tester) async {
      await tester.pumpWidget(
        _host(const AppInfoCard(title: '仅标题', chips: [])),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Wrap), findsNothing);
    });
  });

  testWidgets('AppPanel 承载带分隔线的列表不溢出', (tester) async {
    await tester.pumpWidget(
      _host(
        AppPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ListTile(title: Text('个性签名'), subtitle: Text('一句话')),
              Divider(height: 1),
              ListTile(title: Text('注册时间'), subtitle: Text('2026-09-19')),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSkeleton 关闭动画时不残留定时器', (tester) async {
    AppSkeleton.animate = false;
    addTearDown(() => AppSkeleton.animate = true);

    await tester.pumpWidget(
      _host(const AppSkeletonList(itemCount: 3)),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSkeleton), findsNWidgets(3));
  });

  testWidgets('AppEmptyState 标题 + 说明 + 补充三级文案', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppEmptyState(
          icon: Icons.wifi_off_outlined,
          title: '加载失败',
          message: '加载失败，请检查服务器连接后重试',
          hint: '确认服务器已启动后重试',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('加载失败'), findsOneWidget); // 标题
    expect(
      find.text('加载失败，请检查服务器连接后重试'),
      findsOneWidget,
    ); // 正文
    expect(find.text('确认服务器已启动后重试'), findsOneWidget); // 补充
  });
}
