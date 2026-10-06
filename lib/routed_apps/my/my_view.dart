import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/routed_apps/competition/team_detail_view.dart';
import 'package:debate_cloud/routed_apps/my/my_controller.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class MyCompetitionsPage extends StatefulWidget {
  const MyCompetitionsPage({super.key});

  @override
  State<MyCompetitionsPage> createState() => _MyCompetitionsPageState();
}

class _MyCompetitionsPageState extends State<MyCompetitionsPage> {
  late final MyCompetitionsController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(MyCompetitionsController());
  }

  @override
  void dispose() {
    Get.delete<MyCompetitionsController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const AppPageScaffold(
          title: '我的赛事',
          loadingState: AppSkeletonList(itemCount: 5, showAvatar: false),
        );
      }
      return AppPageScaffold(
        title: '我的赛事',
        onRefresh: controller.load,
        children: [
          const AppSectionHeader(title: '待处理邀请', icon: Icons.mail_outline),
          const SizedBox(height: AppDesign.spaceS),
          controller.invitations.isEmpty
              ? const AppSectionEmpty('暂无邀请')
              : AppResponsiveGrid(
                  maxColumns: 2,
                  children: [
                    for (final i in controller.invitations)
                      if (i.isPending) _inviteCard(context, controller, i),
                  ],
                ),
          const SizedBox(height: AppDesign.spaceL),
          const AppSectionHeader(title: '我的队伍', icon: Icons.groups_outlined),
          const SizedBox(height: AppDesign.spaceS),
          controller.teams.isEmpty
              ? const AppSectionEmpty('暂无队伍')
              : AppResponsiveGrid(
                  maxColumns: 2,
                  children: [for (final t in controller.teams) _teamCard(t)],
                ),
          const SizedBox(height: AppDesign.spaceL),
          const AppSectionHeader(
            title: '报名记录',
            icon: Icons.assignment_outlined,
          ),
          const SizedBox(height: AppDesign.spaceS),
          controller.signups.isEmpty
              ? const AppSectionEmpty('暂无报名')
              : AppResponsiveGrid(
                  maxColumns: 2,
                  children: [for (final s in controller.signups) _signupCard(s)],
                ),
        ],
      );
    });
  }

  Widget _inviteCard(BuildContext context, MyCompetitionsController c, Invitation i) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${i.inviterUsername} 邀请你加入「${i.teamName}」',
            style: text.titleSmall?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppDesign.spaceXXS),
          Text(
            '赛事：${i.competitionName}  ${i.type == 2 ? '教练' : '队员'}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDesign.spaceS),
          // 主题给按钮的 minimumSize 宽度是无穷大（Size.fromHeight），
          // Row 主轴对子项不约束，裸按钮会推出非法约束导致整页布局崩坏；
          // 必须用 Expanded 给按钮有界宽度（与赛事详情页/聊天邀请卡片一致）。
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respond(context, c, i, false),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: FilledButton(
                  onPressed: () => _respond(context, c, i, true),
                  child: const Text('接受'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    MyCompetitionsController c,
    Invitation i,
    bool accept,
  ) async {
    try {
      await c.respond(i, accept);
      AppSnackbar.success('成功', accept ? '已加入队伍' : '已拒绝邀请');
    } on ApiException catch (e) {
      AppSnackbar.error('操作失败', e.message);
    } catch (_) {
      AppSnackbar.error('操作失败', '请检查服务器连接');
    }
  }

  Widget _teamCard(Team t) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: () => Get.to(() => TeamDetailPage(teamId: t.id, teamName: t.name)),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppDesign.radiusM),
            ),
            child: Icon(
              t.isSigned ? Icons.emoji_events_outlined : Icons.groups_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: AppDesign.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: text.titleSmall?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppDesign.spaceXXXS),
                Text(
                  '赛事 ID ${t.competitionId} · 在队 ${t.memberCount} 人',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppStatusChip(
            label: t.isSigned ? '已报名' : '未报名',
            status: t.isSigned ? AppStatus.success : AppStatus.neutral,
          ),
        ],
      ),
    );
  }

  Widget _signupCard(SignupRecord s) {
    final status = switch (s.status) {
      0 => AppStatus.warning,
      1 => AppStatus.success,
      2 => AppStatus.danger,
      _ => AppStatus.neutral,
    };
    return AppInfoCard(
      title: '${s.teamName} → ${s.competitionName}',
      status: status,
      statusLabel: _label(s.status),
      description: s.remark.isEmpty ? null : '备注：${s.remark}',
    );
  }

  String _label(int status) => switch (status) {
    0 => '待审核',
    1 => '已通过',
    2 => '已拒绝',
    _ => '未知',
  };
}
