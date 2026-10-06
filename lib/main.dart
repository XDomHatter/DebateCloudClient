import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_pages.dart';
import 'package:debate_cloud/app/app_routes.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/app/theme_settings.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_page_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
// 视频后端按平台选择：Windows/Linux 挂 media_kit（见 video_backend_io.dart
// 的说明），Web 用 video_player 官方实现（stub）。media_kit 无 Web 支持，
// 必须经条件导入隔离出 Web 编译。默认分支是 io 实现，原因见
// local_media.dart 的说明。
import 'package:debate_cloud/app/video_backend_io.dart'
    if (dart.library.js_interop) 'package:debate_cloud/app/video_backend_stub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initVideoBackend();
  await Cache.init();
  // 必须早于任何 SDK 调用：服务端地址是 HTTP 与 WebSocket 的唯一真源。
  await ServerSettings.load();
  await ChatSettings.load(); // 读回「富文本渲染」开关
  await ThemeSettings.load(); // 读回「浅色 / 深色」主题选择
  Get.put<AuthService>(AuthService()); // Init in GlobalController.onInit
  Get.put<ChatSocket>(ChatSocket()); // 跟随登录态自动连接 WebSocket
  Get.put<NavigationService>(NavigationService()); // Init in MainScaffoldController.onInit
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final controller = Get.put(GlobalController());

  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题选择持久化在 ThemeSettings，切换后全应用即时生效。
    return Obx(
      () => GetMaterialApp(
        title: 'Debate Cloud',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeSettings.mode.value,
      // 转场：与 Tab 内 Navigator 的 appPageRoute 保持同一手感。
      customTransition: AppGetTransition(),
      transitionDuration: AppDesign.normal,
      // 限制系统字体缩放倍率，避免大字号在桌面端破版（纯视觉防护）。
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final textScaler = media.textScaler.clamp(
          minScaleFactor: AppDesign.minTextScale,
          maxScaleFactor: AppDesign.maxTextScale,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: textScaler),
          // 桌面端 Esc 关弹窗。只在**确实有弹窗**时才响应，避免抢走输入框
          // 里的 Esc（例如输入法取消候选）。
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (Get.isDialogOpen == true || Get.isBottomSheetOpen == true) {
                  Get.back<void>();
                }
              },
            },
            child: Focus(autofocus: true, child: child ?? const SizedBox.shrink()),
          ),
        );
      },
        initialRoute: Routes.MAIN,
        getPages: AppPages.routes,
      ),
    );
  }
}

class GlobalController extends GetxController {
  late AuthService authService;

  @override
  void onInit() {
    super.onInit();
    authService = Get.find<AuthService>();
    authService.init();
  }

  bool userAuthed() => authService.isLoggedIn;
}
