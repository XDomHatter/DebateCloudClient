import 'package:flutter/material.dart';

/// 全站设计令牌。
///
/// 页面层只允许引用这里的常量，禁止再写死数值，保证 PC 与移动端视觉一致。
abstract final class AppDesign {
  // ── 断点 ──────────────────────────────────────────────
  /// 小于该宽度为手机形态（单列 + 底部导航）。
  static const double bpMedium = 600;

  /// 大于等于该宽度为桌面形态（侧边导航 + 多列网格）。
  static const double bpExpanded = 1024;

  // ── 内容最大宽度 ──────────────────────────────────────
  /// 列表 / 看板类内容的最大宽度，避免在超宽屏上被拉成一条线。
  static const double maxContentWidth = 1200;

  /// 阅读 / 表单类内容的最大宽度。
  static const double maxReadingWidth = 760;

  /// 登录等单列表单的最大宽度。
  static const double maxFormWidth = 420;

  /// 弹窗最大宽度（桌面端必须限制，否则输入框会被无限拉宽）。
  static const double maxDialogWidth = 480;

  /// 网格卡片的最小宽度，用于自动推算列数。
  static const double minCardWidth = 340;

  /// 桌面端侧边导航栏收起时的宽度（只显示图标）。
  ///
  /// 72 = 居中 40 的图标按钮两侧各留 16。原来是 88，但收起态的行改成
  /// 40×40 方块后两侧各有 24px 死区（且不可点，InkWell 跟着缩到 40 了）。
  static const double railWidth = 72;

  /// 侧边导航展开后的宽度（图标 + 文字 + 二级入口）。
  ///
  /// 仅在 ≥ [bpExpanded] 时允许展开：600–1023 这一档屏幕吃掉 168px 后，
  /// 正文只剩不到 400px，反而更难用。
  ///
  /// 168 是按内容反推的：品牌行 12px 内边距 + 三个主入口 + 二级入口，
  /// 每级都用 [railItemHeight] 的扁平行，168 足够放「20px 图标 + 12px 间距 +
  /// 四字标签」且右侧仍有 20px 余量。
  static const double railWidthExtended = 168;

  /// 侧边导航单项（含一级 Tab 与二级入口）的高度。
  ///
  /// 低于 [controlHeight]（48）但高于触控最低线：导航里项目少、不需要
  /// 48px 的呼吸感，压到 40 才能让两条层级在视觉上等重。
  static const double railItemHeight = 40;

  /// 侧边导航单项之间的间距。
  static const double railItemSpacing = 4;

  /// 侧边导航顶部 Logo 的边长。
  ///
  /// 原本 40 与下方 32px 的指示器抢视觉重心，收到 28 后品牌行更收拢。
  static const double railLogoSize = 28;

  /// 允许展开侧边导航的最小宽度。
  static const double bpRailExtended = bpExpanded;

  /// 列表 + 右侧预览双栏所需的**可用**宽度（已扣掉侧边导航与内边距）。
  ///
  /// 低于这个宽度就退回单栏网格：双栏会把两侧都压得只剩 400 出头，
  /// 列表看不全、预览也读不出东西。
  static const double bpTwoPane = 1000;

  /// 双栏里左侧列表的固定宽度；右侧预览吃掉剩下的。
  static const double twoPaneListWidth = 380;

  // ── 间距 ──────────────────────────────────────────────
  /// 标题与副标题之间的发丝间距。
  ///
  /// 列表行里标题下紧贴一行辅助文字时用（此前各页面散落着裸 `height: 2`）。
  static const double spaceXXXS = 2;

  static const double spaceXXS = 4;
  static const double spaceXS = 8;
  static const double spaceS = 12;
  static const double spaceM = 16;
  static const double spaceL = 24;
  static const double spaceXL = 32;
  static const double spaceXXL = 48;

  // ── 圆角 ──────────────────────────────────────────────
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXL = 20;
  static const double radiusFull = 999;

  // ── 动效 ──────────────────────────────────────────────
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);

  // ── 尺寸 ──────────────────────────────────────────────
  /// 按钮与输入框的最小高度，移动端触控友好、桌面端不显笨重。
  static const double controlHeight = 48;

  /// 系统字体缩放的钳制区间，防止大字号在桌面端破版。
  static const double minTextScale = 0.9;
  static const double maxTextScale = 1.3;
}

/// 基础色板。主色为墨绿 Teal，语义色区分赛事状态。
abstract final class AppPalette {
  // 主色（墨绿）
  static const Color teal50 = Color(0xFFE6F4F1);
  static const Color teal100 = Color(0xFFC2E5DE);
  static const Color teal200 = Color(0xFF8FD3C7);
  static const Color teal400 = Color(0xFF2C9E93);
  static const Color teal500 = Color(0xFF0F766E);
  static const Color teal600 = Color(0xFF0B5C56);
  static const Color teal700 = Color(0xFF094A45);
  static const Color teal900 = Color(0xFF042925);

  // 语义色：浅色模式
  static const Color successLight = Color(0xFF2E9E5B);
  static const Color infoLight = Color(0xFF3B7DDD);
  static const Color warningLight = Color(0xFFD98324);
  static const Color dangerLight = Color(0xFFD0453B);
  static const Color neutralLight = Color(0xFF8A8F98);

  // 语义色：深色模式
  static const Color successDark = Color(0xFF5CC98C);
  static const Color infoDark = Color(0xFF79AEF0);
  static const Color warningDark = Color(0xFFE8A94D);
  static const Color dangerDark = Color(0xFFF08A80);
  static const Color neutralDark = Color(0xFF9AA0A6);

  // 中性底层（不随主题翻转的少量固定色，用于品牌区域）
  static const Color white = Color(0xFFFFFFFF);

  /// 媒体全屏查看器的沉浸式纯黑底。
  ///
  /// 刻意**不**随明暗主题翻转：亮色模式下给图片套灰框会削弱沉浸感，
  /// 深色模式下灰底又会在图片四周留出一圈可见边框。该底色上的文字与
  /// 图标统一用 [white]，与主题色板解耦。
  static const Color black = Color(0xFF000000);
}

/// 抽象状态。具体业务状态（如赛事状态）自行映射到这四个语义槽位。
enum AppStatus { success, info, warning, neutral, danger }

/// 一个语义槽位的前景色与背景色。
class AppStatusStyle {
  final Color foreground;
  final Color background;

  const AppStatusStyle({required this.foreground, required this.background});

  AppStatusStyle lerp(AppStatusStyle? other, double t) => AppStatusStyle(
    foreground: Color.lerp(foreground, other?.foreground, t) ?? foreground,
    background: Color.lerp(background, other?.background, t) ?? background,
  );
}

/// 状态语义色的主题扩展，随明暗主题自动切换。
class AppStatusTheme extends ThemeExtension<AppStatusTheme> {
  final AppStatusStyle success;
  final AppStatusStyle info;
  final AppStatusStyle warning;
  final AppStatusStyle neutral;
  final AppStatusStyle danger;

  const AppStatusTheme({
    required this.success,
    required this.info,
    required this.warning,
    required this.neutral,
    required this.danger,
  });

  static AppStatusTheme light() => const AppStatusTheme(
    success: AppStatusStyle(
      foreground: AppPalette.successLight,
      background: Color(0xFFE8F5ED),
    ),
    info: AppStatusStyle(
      foreground: AppPalette.infoLight,
      background: Color(0xFFE9F1FC),
    ),
    warning: AppStatusStyle(
      foreground: AppPalette.warningLight,
      background: Color(0xFFFDF3E3),
    ),
    neutral: AppStatusStyle(
      foreground: AppPalette.neutralLight,
      background: Color(0xFFF1F2F4),
    ),
    danger: AppStatusStyle(
      foreground: AppPalette.dangerLight,
      background: Color(0xFFFCEDEC),
    ),
  );

  static AppStatusTheme dark() => const AppStatusTheme(
    success: AppStatusStyle(
      foreground: AppPalette.successDark,
      background: Color(0xFF14341F),
    ),
    info: AppStatusStyle(
      foreground: AppPalette.infoDark,
      background: Color(0xFF16273D),
    ),
    warning: AppStatusStyle(
      foreground: AppPalette.warningDark,
      background: Color(0xFF3A2A12),
    ),
    neutral: AppStatusStyle(
      foreground: AppPalette.neutralDark,
      background: Color(0xFF2A2E31),
    ),
    danger: AppStatusStyle(
      foreground: AppPalette.dangerDark,
      background: Color(0xFF3D1E1B),
    ),
  );

  AppStatusStyle of(AppStatus status) => switch (status) {
    AppStatus.success => success,
    AppStatus.info => info,
    AppStatus.warning => warning,
    AppStatus.neutral => neutral,
    AppStatus.danger => danger,
  };

  @override
  AppStatusTheme copyWith({
    AppStatusStyle? success,
    AppStatusStyle? info,
    AppStatusStyle? warning,
    AppStatusStyle? neutral,
    AppStatusStyle? danger,
  }) {
    return AppStatusTheme(
      success: success ?? this.success,
      info: info ?? this.info,
      warning: warning ?? this.warning,
      neutral: neutral ?? this.neutral,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppStatusTheme lerp(covariant AppStatusTheme? other, double t) {
    if (other == null) return this;
    return AppStatusTheme(
      success: success.lerp(other.success, t),
      info: info.lerp(other.info, t),
      warning: warning.lerp(other.warning, t),
      neutral: neutral.lerp(other.neutral, t),
      danger: danger.lerp(other.danger, t),
    );
  }
}

/// 便捷读取状态语义色。
extension AppStatusThemeX on BuildContext {
  AppStatusTheme get statusTheme =>
      Theme.of(this).extension<AppStatusTheme>() ?? AppStatusTheme.light();

  AppStatusStyle statusStyleOf(AppStatus status) => statusTheme.of(status);
}
