import 'package:debate_cloud/app/app_design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 轻提示的语义分类，决定配色与图标。
enum AppSnackKind {
  /// 一般提示（默认）。
  info,

  /// 操作成功。
  success,

  /// 需要注意但不算失败（如「已拒绝」）。
  warning,

  /// 操作失败 / 错误。
  danger,
}

/// 全站统一的轻提示入口。
///
/// **为什么不能直接用 `Get.snackbar`**：它走的是自己内部的默认样式，
/// 完全忽略 `ThemeData.snackBarTheme`——主题里配的 floating 行为、圆角、
/// `inverseSurface` 配色全都不生效，导致提示条与全站视觉脱节，且桌面端
/// 会被拉成贯穿屏幕的一整条。这里显式把主题色、圆角、宽度上限和图标喂
/// 进去，保证明暗主题下都一致。
///
/// 无 `BuildContext` 也能调用（业务代码多在 controller 里报结果），
/// 上下文取 `Get.context`；拿不到时静默丢弃，避免在无路由环境下崩溃。
abstract final class AppSnackbar {
  /// 一般提示。
  static void show(
    String title,
    String message, {
    AppSnackKind kind = AppSnackKind.info,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _emit(title, message, kind: kind, duration: duration);

  /// 成功提示。
  static void success(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) =>
      _emit(title, message, kind: AppSnackKind.success, duration: duration);

  /// 警告提示。
  static void warning(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) =>
      _emit(title, message, kind: AppSnackKind.warning, duration: duration);

  /// 失败 / 错误提示。
  static void error(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 4),
  }) =>
      _emit(title, message, kind: AppSnackKind.danger, duration: duration);

  static void _emit(
    String title,
    String message, {
    required AppSnackKind kind,
    required Duration duration,
  }) {
    final context = Get.context;
    if (context == null) return;

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = context.statusStyleOf(_status(kind));

    // 桌面端宽度限制：不设上限时提示条会横跨整个窗口，视觉重心跑偏。
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = AppDesign.maxDialogWidth;
    final horizontal = screenWidth > maxWidth + AppDesign.spaceL
        ? (screenWidth - maxWidth) / 2
        : AppDesign.spaceM;

    // 这里是 AppSnackbar 自身的实现，必须保持底层的 Get.snackbar 调用，
    // 换成 AppSnackbar.show 会造成无限递归。
    Get.snackbar(
      title,
      message,
      titleText: Row(
        children: [
          Icon(_icon(kind), size: 18, color: style.foreground),
          const SizedBox(width: AppDesign.spaceXS),
          Expanded(
            child: Text(
              title,
              style: text.titleSmall?.copyWith(color: style.foreground),
            ),
          ),
        ],
      ),
      messageText: Text(
        message,
        style: text.bodySmall?.copyWith(color: style.foreground),
      ),
      snackPosition: SnackPosition.BOTTOM,
      duration: duration,
      animationDuration: AppDesign.normal,
      isDismissible: true,
      // Get 的默认背景是固定深色，这里换成语义浅底 + 深字，与 AppStatusChip
      // 的观感保持同一套语言。
      backgroundColor: style.background,
      borderRadius: AppDesign.radiusM,
      margin: EdgeInsets.fromLTRB(
        horizontal,
        AppDesign.spaceM,
        horizontal,
        AppDesign.spaceM,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spaceM,
        vertical: AppDesign.spaceS,
      ),
      borderColor: style.foreground.withValues(alpha: 0.35),
      borderWidth: 1,
      // 语义浅底上不需要再叠一层默认的半透明黑遮罩。
      overlayBlur: 0,
      barBlur: 0,
      // 底部进度条用同色系淡色，不抢正文注意力。
      progressIndicatorBackgroundColor: style.foreground.withValues(
        alpha: 0.18,
      ),
      shouldIconPulse: false,
      icon: const SizedBox.shrink(),
      // 语义浅底上的文字必须显式指定，否则 Get 会用默认的白色 onColor。
      colorText: style.foreground,
      boxShadows: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: 0.14),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  static AppStatus _status(AppSnackKind kind) => switch (kind) {
    AppSnackKind.success => AppStatus.success,
    AppSnackKind.warning => AppStatus.warning,
    AppSnackKind.danger => AppStatus.danger,
    AppSnackKind.info => AppStatus.info,
  };

  static IconData _icon(AppSnackKind kind) => switch (kind) {
    AppSnackKind.success => Icons.check_circle_outline,
    AppSnackKind.warning => Icons.warning_amber_outlined,
    AppSnackKind.danger => Icons.error_outline,
    AppSnackKind.info => Icons.info_outline,
  };
}
