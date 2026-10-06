// 回归测试：自绘悬停提示 AppTooltip。
//
// 它存在的唯一理由是绕开 Windows 上 material `Tooltip` 的引擎 Bug
// （flutter/flutter#182444，P2，3.41.6 未修）：相邻两个 tooltip 之间悬停切换时，
// overlay 的语义节点先被 detach、traversal parent 收不到通知，于是刷
// `Failed to update ui::AXTree ... is not the new root`。
// 所以这里除了常规行为，还要钉住「没有退化回 material Tooltip」。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key _target = Key('target');

Widget _host(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

/// 桌面端鼠标悬停必须走真的鼠标事件，`tap` 触发不了 MouseRegion.onEnter。
Future<TestGesture> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets('悬停等待后显示气泡', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: AppTooltip(
            message: '刷新',
            child: SizedBox(key: _target, width: 40, height: 40),
          ),
        ),
      ),
    );

    expect(find.text('刷新'), findsNothing);
    await _hover(tester, find.byKey(_target));
    // 还不到 waitDuration，气泡不该出现（否则划过一排图标会连闪）。
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('刷新'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('刷新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移出后立即移除气泡', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: AppTooltip(
            message: '刷新',
            child: SizedBox(key: _target, width: 40, height: 40),
          ),
        ),
      ),
    );

    final gesture = await _hover(tester, find.byKey(_target));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('刷新'), findsOneWidget);

    await gesture.moveTo(const Offset(400, 600));
    await tester.pump();
    expect(find.text('刷新'), findsNothing);
  });

  testWidgets('没有 Overlay 祖先时静默降级', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AppTooltip(
          message: '刷新',
          child: SizedBox(key: _target, width: 40, height: 40),
        ),
      ),
    );

    await _hover(tester, find.byKey(_target));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('刷新'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 回归：Overlay 给 entry 的是整屏**紧约束**，follower 会 `size = biggest`
  // 并原样透传，ConstrainedBox(maxWidth) 会被 enforce 反向 clamp 成整屏，
  // 气泡变成一个盖住半屏的实心块（暗色主题下看着就是「白屏」）。
  // 必须靠 Align 把约束松开、并把气泡那个角钉在锚点上。
  testWidgets('气泡按内容收缩，不铺满屏幕', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: AppTooltip(
            message: '刷新',
            child: SizedBox(key: _target, width: 40, height: 40),
          ),
        ),
      ),
    );
    await _hover(tester, find.byKey(_target));
    await tester.pump(const Duration(milliseconds: 400));

    final bubble = tester.renderObject<RenderBox>(find.byType(DecoratedBox).first);
    expect(bubble.size.width, lessThan(160));
    expect(bubble.size.height, lessThan(60));

    // 水平居中、紧跟在目标下方 verticalOffset 处。
    final target = tester.getRect(find.byKey(_target));
    expect(bubble.localToGlobal(Offset.zero).dx + bubble.size.width / 2,
        closeTo(target.center.dx, 1));
    expect(bubble.localToGlobal(Offset.zero).dy, closeTo(target.bottom + 8, 1));
  });

  testWidgets('下方空间不足时翻到目标上方', (tester) async {
    await tester.pumpWidget(
      _host(
        const Align(
          alignment: Alignment.bottomCenter,
          child: AppTooltip(
            message: '刷新',
            child: SizedBox(key: _target, width: 40, height: 40),
          ),
        ),
      ),
    );
    await _hover(tester, find.byKey(_target));
    await tester.pump(const Duration(milliseconds: 400));

    final bubble = tester.renderObject<RenderBox>(find.byType(DecoratedBox).first);
    final target = tester.getRect(find.byKey(_target));
    expect(bubble.localToGlobal(Offset.zero).dy + bubble.size.height,
        closeTo(target.top - 8, 1));
  });

  testWidgets('配色取 inverseSurface / onInverseSurface', (tester) async {
    final theme = AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: const Center(
            child: AppTooltip(
              message: '刷新',
              child: SizedBox(key: _target, width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await _hover(tester, find.byKey(_target));
    await tester.pump(const Duration(milliseconds: 400));

    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration as BoxDecoration).color, theme.colorScheme.inverseSurface);
    expect(
      tester.widget<Text>(find.text('刷新')).style?.color,
      theme.colorScheme.onInverseSurface,
    );
  });

  testWidgets('没退化回 material 的 Tooltip', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppTooltip(
          message: '刷新',
          child: SizedBox(key: _target, width: 40, height: 40),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(AppTooltip), findsOneWidget);
  });
}
