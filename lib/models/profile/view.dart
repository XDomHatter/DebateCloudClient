import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/app/theme_settings.dart';
import 'package:debate_cloud/models/profile/controller.dart';
import 'package:debate_cloud/routed_apps/login/view.dart';
import 'package:debate_cloud/routed_apps/manager/manager_view.dart';
import 'package:debate_cloud/routed_apps/my/my_view.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:debate_cloud/widgets/server_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class ProfileView extends StatelessWidget {
  ProfileView({super.key});

  final ProfileController controller = Get.put(ProfileController());

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.auth.isLoggedIn) {
        return AppPageScaffold(title: '我的', body: _buildGuestView(context));
      }

      final profile = controller.auth.userProfile.value;
      if (profile == null) {
        if (controller.isLoading.value) {
          return const AppPageScaffold(
            title: '我的',
            loadingState: AppLoading(),
          );
        }
        return AppPageScaffold(
          title: '我的',
          maxWidth: AppDesign.maxReadingWidth,
          children: [
            AppEmptyState(
              icon: Icons.person_off_outlined,
              message: controller.errorMessage.value.isEmpty
                  ? '资料加载失败'
                  : controller.errorMessage.value,
              // 服务器下线时这里是用户唯一的落脚点，必须告诉他地址可以改。
              hint: '若服务器地址已变更，可在右上角修改',
              actionLabel: '重试',
              onAction: controller.refreshProfile,
            ),
          ],
        );
      }
      return AppPageScaffold(
        title: '我的',
        onRefresh: controller.refreshProfile,
        maxWidth: AppDesign.maxReadingWidth,
        children: [
          ResponsiveColumns(
            left: _buildSummaryCard(context, profile),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildInfoCard(context, profile),
                const SizedBox(height: AppDesign.spaceM),
                _buildAppearanceCard(),
                const SizedBox(height: AppDesign.spaceM),
                _buildServerCard(context),
                const SizedBox(height: AppDesign.spaceM),
                _buildActions(profile),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// 未登录视图。
  Widget _buildGuestView(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppDesign.maxFormWidth),
          child: AppCard(
            padding: const EdgeInsets.all(AppDesign.spaceL),
            child: Column(
              children: [
                const SizedBox(height: AppDesign.spaceS),
                _buildGuestAvatar(context),
                const SizedBox(height: AppDesign.spaceM),
                Text('尚未登录', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppDesign.spaceXS),
                Text(
                  '登录后可查看并编辑个人资料',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.appSubtleColor),
                ),
                const SizedBox(height: AppDesign.spaceL),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Get.find<NavigationService>().toGlobal(LoginView()),
                    icon: const Icon(Icons.login, size: 20),
                    label: const Text('登录 / 注册'),
                  ),
                ),
                const SizedBox(height: AppDesign.spaceL),
                // 主题切换：登录前也能选浅色 / 深色。
                _ThemeSelector(),
                const SizedBox(height: AppDesign.spaceM),
                // 服务器地址：登录前同样要能改，否则连不上时无处下手。
                _buildServerCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestAvatar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person_outline, size: 44, color: scheme.onSurfaceVariant),
    );
  }

  Widget _buildSummaryCard(BuildContext context, UserProfile profile) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spaceM,
        AppDesign.spaceL,
        AppDesign.spaceM,
        AppDesign.spaceL,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            _buildAvatar(context, profile),
            const SizedBox(height: AppDesign.spaceM),
            Text(
              profile.nickname.isNotEmpty ? profile.nickname : profile.username,
              style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDesign.spaceXXS),
            Text('ID: ${profile.userId}', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (profile.email.isNotEmpty) ...[
              const SizedBox(height: AppDesign.spaceXXS),
              Text(profile.email, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, UserProfile profile) {
    // 内部自带分隔线，用无描边的分组容器而非卡片，避免「卡里套卡」。
    return AppPanel(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('个性签名'),
            subtitle: Text(profile.bio.isEmpty ? '还没有填写签名' : profile.bio),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('注册时间'),
            subtitle: Text(profile.createdAt.isEmpty ? '未知' : profile.createdAt),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.update_outlined),
            title: const Text('最近更新'),
            subtitle: Text(profile.updatedAt.isEmpty ? '未知' : profile.updatedAt),
          ),
        ],
      ),
    );
  }

  /// 外观设置卡片：浅色 / 深色切换。
  Widget _buildAppearanceCard() {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.palette_outlined),
          const SizedBox(width: AppDesign.spaceS),
          const Text('外观'),
          const Spacer(),
          _ThemeSelector(),
        ],
      ),
    );
  }

  /// 服务器地址卡片：点开与登录页同一个设置弹窗，右侧常驻显示当前地址。
  Widget _buildServerCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => ServerSettingsDialog.open<void>(),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined),
          const SizedBox(width: AppDesign.spaceS),
          const Text('服务器'),
          const SizedBox(width: AppDesign.spaceS),
          Expanded(
            child: Obx(
              () => Text(
                ServerSettings.display,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppDesign.spaceXXS),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }

  Widget _buildActions(UserProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => Get.to(() => MyCompetitionsPage()),
          icon: const Icon(Icons.groups_outlined, size: 20),
          label: const Text('我的赛事（队伍 / 邀请 / 报名）'),
        ),
        const SizedBox(height: AppDesign.spaceXS),
        OutlinedButton.icon(
          onPressed: () => Get.to(() => ManagerHomePage()),
          icon: const Icon(Icons.verified_user_outlined, size: 20),
          label: const Text('赛事审批（管理员）'),
        ),
        const SizedBox(height: AppDesign.spaceM),
        FilledButton.tonalIcon(
          onPressed: () => _showEditDialog(profile),
          icon: const Icon(Icons.edit_outlined, size: 20),
          label: const Text('编辑资料'),
        ),
        const SizedBox(height: AppDesign.spaceXS),
        OutlinedButton.icon(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout, size: 20),
          label: const Text('退出登录'),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, UserProfile profile) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: controller.changeAvatar,
      child: Stack(
        children: [
          Obx(
            () => Opacity(
              opacity: controller.isSaving.value ? 0.5 : 1,
              child: CircleAvatar(
                radius: 52,
                backgroundColor: scheme.primaryContainer,
                // 头像圆直径 104 逻辑像素，按 2x 物理像素解码即可，
                // 不必把原图整幅位图搬进显存。
                backgroundImage: profile.avatar == null
                    ? null
                    : ResizeImage(profile.avatar!.imageProvider(), width: 256),
                child: profile.avatar == null
                    ? Icon(Icons.person, size: 52, color: scheme.onPrimaryContainer)
                    : null,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(AppDesign.spaceXXS + 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: context.appCardColor, width: 2),
              ),
              child: Icon(Icons.photo_camera, size: 14, color: scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(UserProfile profile) {
    final nicknameCtrl = TextEditingController(text: profile.nickname);
    final bioCtrl = TextEditingController(text: profile.bio);
    Get.dialog(
      AppDialog(
        title: '编辑资料',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nicknameCtrl,
              maxLength: 20,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: AppDesign.spaceM),
            TextField(
              controller: bioCtrl,
              minLines: 2,
              maxLines: 4,
              maxLength: 140,
              decoration: const InputDecoration(labelText: '个性签名', alignLabelWithHint: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          Obx(
            () => FilledButton(
              onPressed: controller.isSaving.value
                  ? null
                  : () async {
                      final ok = await controller.saveProfile(nicknameCtrl.text.trim(), bioCtrl.text.trim());
                      if (ok) {
                        Get.back();
                        AppSnackbar.show('提示', '资料已更新');
                      } else {
                        AppSnackbar.error('保存失败', '请稍后重试');
                      }
                    },
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    Get.dialog(
      AppDialog(
        title: '退出登录',
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Get.back();
              controller.logout();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

/// 浅色 / 深色分段切换控件，选中态跟随 [ThemeSettings.mode]。
///
/// 用 Obx 包裹 SegmentedButton，点按后写入 [ThemeSettings]，主题经
/// main.dart 的 Obx 绑定立即全局生效。
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            label: Text('深色'),
          ),
        ],
        selected: {ThemeSettings.mode.value},
        onSelectionChanged: (selection) {
          ThemeSettings.setMode(selection.first);
        },
        showSelectedIcon: false,
      ),
    );
  }
}
