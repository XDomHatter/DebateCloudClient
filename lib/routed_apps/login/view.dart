import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/routed_apps/login/controller.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginView extends StatelessWidget {
  LoginView({super.key});

  final controller = Get.put(LoginController());

  final TextEditingController userCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController confirmCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(controller.isRegisterMode.value ? "注册" : "登录")),
        // 连不上服务器时第一反应就是改地址，所以登录前也要能改。
        actions: [
          AppTooltip(
            message: '服务器设置',
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () => ServerSettingsDialog.open<void>(),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDesign.spaceM),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppDesign.maxFormWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDesign.spaceM),
                _buildBrand(context),
                const SizedBox(height: AppDesign.spaceL),
                AppCard(
                  padding: const EdgeInsets.all(AppDesign.spaceL),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: userCtrl,
                        decoration: const InputDecoration(
                          labelText: "用户名",
                          prefixIcon: Icon(Icons.person_outline, size: 20),
                        ),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        onChanged: (v) => controller.username.value = v,
                      ),
                      Obx(
                        () => controller.isRegisterMode.value
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  top: AppDesign.spaceM,
                                ),
                                child: TextField(
                                  controller: emailCtrl,
                                  decoration: const InputDecoration(
                                    labelText: "邮箱",
                                    prefixIcon: Icon(Icons.mail_outline, size: 20),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  onChanged: (v) => controller.email.value = v,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: AppDesign.spaceM),
                        child: TextField(
                          controller: passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: "密码",
                            prefixIcon: Icon(Icons.lock_outline, size: 20),
                          ),
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.password],
                          onChanged: (v) => controller.password.value = v,
                        ),
                      ),
                      Obx(
                        () => controller.isRegisterMode.value
                            ? Padding(
                                padding: const EdgeInsets.only(
                                  top: AppDesign.spaceM,
                                ),
                                child: TextField(
                                  controller: confirmCtrl,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: "确认密码",
                                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onChanged: (v) =>
                                      controller.confirmPassword.value = v,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: AppDesign.spaceL),
                      Obx(
                        () => FilledButton(
                          onPressed: controller.isLoading.value
                              ? null
                              : controller.isRegisterMode.value
                                  ? controller.register
                                  : controller.login,
                          child: controller.isLoading.value
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                )
                              : Text(
                                  controller.isRegisterMode.value ? "注册" : "登录",
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDesign.spaceXS),
                TextButton(
                  onPressed: controller.isLoading.value
                      ? null
                      : () {
                          controller.toggleMode();
                          emailCtrl.clear();
                          confirmCtrl.clear();
                        },
                  child: Obx(
                    () => Text(
                      controller.isRegisterMode.value
                          ? "已有账号？去登录"
                          : "没有账号？立即注册",
                    ),
                  ),
                ),
                const SizedBox(height: AppDesign.spaceS),
                // 常驻显示当前地址：连不上时能一眼确认打到哪台机器。
                Obx(
                  () => Text(
                    "当前服务器 ${ServerSettings.display}",
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrand(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppDesign.radiusL),
          ),
          child: Icon(Icons.forum_outlined, size: 28, color: scheme.onPrimary),
        ),
        const SizedBox(height: AppDesign.spaceM),
        Text(
          'Debate Cloud',
          style: text.headlineSmall?.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: AppDesign.spaceXXS),
        Text(
          '辩论赛事一站式管理平台',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
