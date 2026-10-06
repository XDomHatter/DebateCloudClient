import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/routed_apps/chat/chat_detail_view.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_server_action.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class UserProfileController extends GetxController {
  UserProfileController(this.targetUserId);

  final int targetUserId;
  final auth = Get.find<AuthService>();

  final profile = Rxn<PublicProfile>();
  final isLoading = false.obs;
  final isSending = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      profile.value = await SDK.fetchPublicProfile(
        auth.userObj.value,
        userId: targetUserId,
      );
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      errorMessage.value = e is ApiException
          ? e.message
          : '加载失败，请检查服务器连接后重试';
    } finally {
      isLoading.value = false;
    }
  }

  /// 发送好友申请，成功后刷新以更新按钮状态。
  Future<bool> sendFriendRequest() async {
    isSending.value = true;
    try {
      await ChatSDK.sendFriendRequest(auth.userObj.value, targetUserId, '');
      await load();
      AppSnackbar.success('已发送', '等待对方通过好友申请');
      return true;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isSending.value = false;
    }
    return false;
  }
}

/// 公开个人主页。任意位置点击他人头像进入，只展示公开资料，不含 email。
class UserProfilePage extends StatefulWidget {
  final int userId;

  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final UserProfileController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      UserProfileController(widget.userId),
      tag: 'user-profile-${widget.userId}',
    );
  }

  @override
  void dispose() {
    Get.delete<UserProfileController>(tag: 'user-profile-${widget.userId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final p = controller.profile.value;
      if (p == null) {
        if (controller.isLoading.value) {
          return AppPageScaffold(
            appBar: _appBar(),
            loadingState: const AppLoading(),
          );
        }
        return AppPageScaffold(
          appBar: _appBar(),
          maxWidth: AppDesign.maxReadingWidth,
          children: [
            AppEmptyState(
              icon: Icons.person_off_outlined,
              message: controller.errorMessage.value.isEmpty
                  ? '资料加载失败'
                  : controller.errorMessage.value,
              actionLabel: '重试',
              onAction: controller.load,
            ),
          ],
        );
      }
      return AppPageScaffold(
        appBar: _appBar(),
        onRefresh: controller.load,
        maxWidth: AppDesign.maxReadingWidth,
        children: [
          _summaryCard(context, p),
          const SizedBox(height: AppDesign.spaceM),
          _infoCard(context, p),
          if (!p.isSelf && !p.cancelled) ...[
            const SizedBox(height: AppDesign.spaceM),
            _actions(context, p),
          ],
        ],
      );
    });
  }

  /// 标题跟随加载结果（个人主页 → 昵称），所以整页都放在 Obx 里。
  AppBar _appBar() => AppBar(
    title: Obx(
      () => Text(controller.profile.value?.displayName ?? '个人主页'),
    ),
    // 传了自定义 appBar 就绕开了 AppPageScaffold 的内置入口，这里要自己补上：
    // 服务端下线时这类「错误态整块替换内容」的页面正是最需要改地址的地方。
    actions: const [AppServerAction()],
  );

  Widget _summaryCard(BuildContext context, PublicProfile p) {
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
            ChatAvatar(
              userId: p.userId,
              name: p.displayName,
              hasAvatar: p.hasAvatar,
              avatarUpdatedAt: p.avatarUpdatedAt,
              radius: 52,
            ),
            const SizedBox(height: AppDesign.spaceM),
            Text(
              p.displayName,
              style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDesign.spaceXXS),
            Text(
              'ID: ${p.userId}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppDesign.spaceXXS),
            Text(
              '用户名：${p.username}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (p.cancelled) ...[
              const SizedBox(height: AppDesign.spaceS),
              const AppStatusChip(label: '账号已注销', status: AppStatus.neutral),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, PublicProfile p) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppDesign.spaceXS),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('个性签名'),
            subtitle: Text(p.bio.isEmpty ? '还没有填写签名' : p.bio),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('注册时间'),
            subtitle: Text(p.createdAt.isEmpty ? '未知' : p.createdAt),
          ),
        ],
      ),
    );
  }

  /// 好友操作区：好友可直接发消息，非好友按申请状态展示加好友入口。
  Widget _actions(BuildContext context, PublicProfile p) {
    if (p.isFriend) {
      return FilledButton.tonalIcon(
        onPressed: () => _openChat(p),
        icon: const Icon(Icons.chat_bubble_outline, size: 20),
        label: const Text('发消息'),
      );
    }
    if (p.requestSent) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_top_outlined, size: 20),
        label: const Text('已发送好友申请'),
      );
    }
    return Obx(
      () => FilledButton.icon(
        onPressed: controller.isSending.value
            ? null
            : controller.sendFriendRequest,
        icon: const Icon(Icons.person_add_alt_1, size: 20),
        label: const Text('加好友'),
      ),
    );
  }

  void _openChat(PublicProfile p) {
    Get.to(
      () => ChatDetailPage(
        friend: Friend(
          userId: p.userId,
          username: p.username,
          nickname: p.nickname,
          hasAvatar: p.hasAvatar,
          avatarUpdatedAt: p.avatarUpdatedAt,
          online: false,
          unreadCount: 0,
          lastMessage: '',
          lastMessageAt: '',
        ),
      ),
    );
  }
}
