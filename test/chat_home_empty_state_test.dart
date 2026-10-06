// 回归测试：消息 tab 首页顶部区块（入口行 + 空态 / 错误态）必须共用同一宽度上限，
// 空态的视觉中心要与入口行中线重合。
//
// 根因：父 Column 是 crossAxisAlignment: start，子项拿到的是**松散**宽度约束（0..1200），
// 只左对齐、不拉伸。入口行（Row + Expanded）在有界松散约束下取满 560；而 AppEmptyState
// 是「自身收缩包裹 + 内部居中」，宽度只有 max(图标 64, 文案固有宽) + 48 ≈ 272。
// 于是两者共享左边界、中心相差 (560 - 272) / 2 ≈ 144px，空态明显偏左。
//
// 只加 Center 或只加 SizedBox(width: infinity) 都不够：
// - Center 在松散约束下会收缩包裹到子项宽度，等于没加；
// - 只加 SizedBox(width: infinity) 时，AppEmptyState 内部仍是松散约束，内容依旧贴左。
// 必须「先限宽 → 再撑满给出紧约束 → 再居中」，见 view.dart 的 _topSection。
//
// 注意：这里不能用 SizedBox.expand —— ListView 主轴高度无界，height: infinity
// 会被收敛成 0，空态直接被压没。
//
// 与 button_infinite_width_test 一样复刻约束环境；必须使用真实 AppTheme。
import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 与 view.dart 的 _topSectionMaxWidth 保持一致。
const double _topSectionMaxWidth = 560;

final _rowKey = GlobalKey();
final _emptyKey = GlobalKey();

/// fixed = 修复后写法；broken = 修复前的裸 AppEmptyState（用于锁定问题复现）。
enum _Variant { fixed, broken }

Widget _host(_Variant variant) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppDesign.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _topSectionMaxWidth),
                    child: Row(
                      key: _rowKey,
                      children: const [
                        Expanded(child: SizedBox(height: 50, child: Text('好友'))),
                        SizedBox(width: AppDesign.spaceS),
                        Expanded(child: SizedBox(height: 50, child: Text('好友申请'))),
                        SizedBox(width: AppDesign.spaceS),
                        Expanded(child: SizedBox(height: 50, child: Text('通知'))),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDesign.spaceL),
                  switch (variant) {
                    _Variant.fixed => ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _topSectionMaxWidth),
                      child: SizedBox(
                        width: double.infinity,
                        child: Center(
                          child: AppEmptyState(
                            key: _emptyKey,
                            icon: Icons.forum_outlined,
                            message: '暂无会话，去添加好友或发起群聊吧',
                            verticalPadding: AppDesign.spaceM,
                          ),
                        ),
                      ),
                    ),
                    _Variant.broken => AppEmptyState(
                      key: _emptyKey,
                      icon: Icons.forum_outlined,
                      message: '暂无会话，去添加好友或发起群聊吧',
                      verticalPadding: AppDesign.spaceM,
                    ),
                  },
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
  testWidgets('修复后：空态中心与入口行中线重合', (tester) async {
    await tester.pumpWidget(_host(_Variant.fixed));

    final row = tester.getRect(find.byKey(_rowKey));
    final empty = tester.getRect(find.byKey(_emptyKey));

    expect(tester.takeException(), isNull);
    expect(row.width, _topSectionMaxWidth);
    expect((row.center.dx - empty.center.dx).abs(), lessThan(1));
  });

  testWidgets('问题复现：空态裸放在左对齐 Column 中会偏左', (tester) async {
    await tester.pumpWidget(_host(_Variant.broken));

    final row = tester.getRect(find.byKey(_rowKey));
    final empty = tester.getRect(find.byKey(_emptyKey));

    expect(tester.takeException(), isNull);
    expect(empty.width, lessThan(_topSectionMaxWidth));
    expect(empty.center.dx, lessThan(row.center.dx - 50));
  });
}
