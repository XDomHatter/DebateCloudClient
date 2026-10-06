import 'package:debate_cloud/app/app_design.dart';
import 'package:flutter/material.dart';

/// 应用主题。
///
/// 提供浅色 / 深色两套 ThemeData，并把全站组件外观集中在组件主题里配置，
/// 页面层不再单独设置颜色与形状。
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.teal500,
      brightness: brightness,
      primary: AppPalette.teal500,
    );
    final text = _textTheme(scheme);

    final cardColor = isDark ? scheme.surfaceContainerHigh : scheme.surface;
    final borderColor = scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDesign.radiusM),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? scheme.surface
          : scheme.surfaceContainerLow,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppStatusTheme.dark() : AppStatusTheme.light(),
      ],
      textTheme: text,
      visualDensity: VisualDensity.standard,

      // ── AppBar ───────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
      ),

      // ── 卡片 ─────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusL),
          side: BorderSide(color: borderColor),
        ),
      ),

      // ── 输入 ─────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHigh : scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spaceM,
          vertical: 14,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),

      // ── 按钮 ─────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDesign.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceL),
          shape: controlShape,
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDesign.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceL),
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDesign.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceL),
          shape: controlShape,
          textStyle: text.labelLarge,
          side: BorderSide(color: borderColor),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDesign.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDesign.spaceM),
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),

      // ── 标签 / 列表 / 分割线 ──────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesign.spaceM,
          vertical: AppDesign.spaceXXS,
        ),
        minVerticalPadding: AppDesign.spaceS,
        iconColor: scheme.primary,
        titleTextStyle: text.titleSmall?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: 0.55),
      ),

      // ── 弹窗 ─────────────────────────────────────────
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: isDark ? scheme.surfaceContainerHigh : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusXL),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppDesign.spaceL,
          AppDesign.spaceXS,
          AppDesign.spaceL,
          AppDesign.spaceL,
        ),
      ),

      // ── 导航 ─────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary);
          }
          return IconThemeData(color: scheme.onSurfaceVariant);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = text.labelMedium ?? const TextStyle(fontSize: 12);
          return base.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: Colors.transparent,
        minWidth: AppDesign.railWidth,
        groupAlignment: -0.9,
        labelType: NavigationRailLabelType.all,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      // ── 其它 ─────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusM),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    const base = TextTheme(
      displaySmall: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, height: 1.25),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, height: 1.3),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.35),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6),
      bodySmall: TextStyle(fontSize: 12, height: 1.5),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
    );
    return base.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}

/// 页面层常用的几个派生色，避免在业务代码里重复判断明暗。
extension AppContextColors on BuildContext {
  Color get appCardColor {
    final scheme = Theme.of(this).colorScheme;
    return scheme.brightness == Brightness.dark
        ? scheme.surfaceContainerHigh
        : scheme.surface;
  }

  Color get appBorderColor {
    final scheme = Theme.of(this).colorScheme;
    return scheme.outlineVariant.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.5 : 0.7,
    );
  }

  Color get appSubtleColor => Theme.of(this).colorScheme.onSurfaceVariant;
}
