import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class LoginController extends GetxController {
  final username = ''.obs;
  final password = ''.obs;
  final email = ''.obs;
  final confirmPassword = ''.obs;

  /// When true the form collects registration fields instead of logging in.
  final isRegisterMode = false.obs;
  final isLoading = false.obs;

  final auth = Get.find<AuthService>();
  final nav = Get.find<NavigationService>();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static bool isValidEmail(String value) => _emailPattern.hasMatch(value);

  void toggleMode() {
    isRegisterMode.toggle();
    email.value = '';
    confirmPassword.value = '';
  }

  Future<void> login() async {
    if (username.value.isEmpty || password.value.isEmpty) {
      AppSnackbar.error("错误", "请输入账号和密码");
      return;
    }

    isLoading.value = true;

    try {
      await _loginAndResume();
    } catch (e) {
      AppSnackbar.error("登录失败", e.toString());
      debugPrint(e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> register() async {
    if (username.value.isEmpty || password.value.isEmpty || email.value.isEmpty) {
      AppSnackbar.error("错误", "请填写用户名、邮箱和密码");
      return;
    }
    if (!isValidEmail(email.value)) {
      AppSnackbar.error("错误", "请输入正确的邮箱地址");
      return;
    }
    if (password.value.length < 6) {
      AppSnackbar.error("错误", "密码长度至少为 6 位");
      return;
    }
    if (password.value != confirmPassword.value) {
      AppSnackbar.error("错误", "两次输入的密码不一致");
      return;
    }

    isLoading.value = true;
    try {
      final result = await SDK.register(username.value, password.value, email.value);
      if (result == RegisterResult.exists) {
        AppSnackbar.error("注册失败", "该用户名已被注册");
        return;
      }

      // 注册成功：清空注册字段并切回登录模式，让用户用新账号登录。
      AppSnackbar.success("注册成功", "请使用新账号登录");
      toggleMode();
    } catch (e) {
      AppSnackbar.error("注册失败", "请检查服务器连接后重试");
      debugPrint(e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loginAndResume() async {
    final UserObj r = await SDK.login(username.value, password.value);
    if (r.isAnonymous) throw Exception("用户名或密码错误");
    auth.login(r);

    // 关闭登录页
    Get.back();

    // 恢复之前被拦截的页面
    nav.resumePending();
  }
}
