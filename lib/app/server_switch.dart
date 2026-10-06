import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';
import 'package:get/get.dart';

/// 换服务器后当前登录态的归宿。
enum ServerSwitchOutcome {
  /// 会话保留：本来就没登录，或新地址仍然接受当前 token（例如只改了端口）。
  kept,

  /// 新地址明确拒绝当前 token，已登出。
  rejected,

  /// 新地址连不上。登录态**不动**，用户改回正确地址还能继续用。
  unreachable,
}

/// 服务端地址变更后的会话处置。
///
/// 之所以单独成文件而不是写在设置弹窗里：这段逻辑要在没有 widget 树的环境
/// 下验证（弹窗测试里 `ChatSocket` 的重连定时器会不断造帧，`pumpAndSettle`
/// 永远等不到静止），而且「明确拒绝」与「连不上」必须严格区分——后者销毁
/// 会话会让用户在改回正确地址后还得重新登录。
abstract final class ServerSwitch {
  static Future<ServerSwitchOutcome> apply(AuthService auth) async {
    if (!auth.isLoggedIn) {
      Get.find<ChatSocket>().reconnect();
      AppSnackbar.success('服务器已更新', ServerSettings.baseUrl);
      return ServerSwitchOutcome.kept;
    }

    final outcome = await _verifyAgainstNewServer(auth);
    switch (outcome) {
      case ServerSwitchOutcome.kept:
        Get.find<ChatSocket>().reconnect();
        AppSnackbar.success('服务器已更新', '${ServerSettings.display} · 登录状态保持');
      case ServerSwitchOutcome.rejected:
        await auth.logout();
        AppSnackbar.show('已切换服务器', '${ServerSettings.display} · 请重新登录');
      case ServerSwitchOutcome.unreachable:
        // 连不上也要让长连接指向新地址，它自己会退避重试；但不碰会话。
        Get.find<ChatSocket>().reconnect();
        AppSnackbar.warning('服务器已更新', '${ServerSettings.display} · 暂无法连接');
    }
    return outcome;
  }

  /// 用新地址校验当前 token。网络异常与「明确拒绝」必须分开判定，所以不能
  /// 用一句 try/catch 兜住。
  static Future<ServerSwitchOutcome> _verifyAgainstNewServer(AuthService auth) async {
    try {
      await SDK.verifySession(auth.userObj.value);
    } on AuthExpiredException {
      return ServerSwitchOutcome.rejected;
    } catch (_) {
      return ServerSwitchOutcome.unreachable;
    }
    // token 被接受了：资料要按新服务端重新拉一份。
    await auth.refreshProfile();
    return ServerSwitchOutcome.kept;
  }
}
