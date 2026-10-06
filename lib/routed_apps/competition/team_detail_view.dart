import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/routed_apps/competition/team_detail_controller.dart';
import 'package:debate_cloud/routed_apps/user/user_profile_view.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TeamDetailPage extends StatefulWidget {
  final int teamId;
  final String? teamName;

  const TeamDetailPage({super.key, required this.teamId, this.teamName});

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  late final TeamDetailController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      TeamDetailController(teamId: widget.teamId),
      tag: 'team-detail-${widget.teamId}',
    );
  }

  @override
  void dispose() {
    Get.delete<TeamDetailController>(tag: 'team-detail-${widget.teamId}');
    super.dispose();
  }

  static (String, AppStatus?) _roleBadge(int type) => switch (type) {
    1 => ('队长', AppStatus.info),
    2 => ('教练', AppStatus.warning),
    _ => ('队员', null),
  };

  static String _joinedAtText(String raw) {
    final date = raw.split(' ').first;
    return date.isEmpty ? '加入时间未知' : '加入于 $date';
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = controller.detail.value;
      if (d == null) {
        if (controller.isLoading.value) {
          return AppPageScaffold(
            title: widget.teamName ?? '队伍详情',
            loadingState: const AppLoading(),
          );
        }
        return AppPageScaffold(
          title: widget.teamName ?? '队伍详情',
          children: [
            AppEmptyState(
              icon: Icons.error_outline,
              message: controller.errorMessage.value,
              actionLabel: '重试',
              onAction: controller.load,
            ),
          ],
        );
      }
      return AppPageScaffold(
        title: widget.teamName ?? '队伍详情',
        onRefresh: controller.load,
        children: [
          _teamInfo(context, d.team),
          const SizedBox(height: AppDesign.spaceL),
          const AppSectionHeader(title: '队员列表', icon: Icons.groups_outlined),
          const SizedBox(height: AppDesign.spaceS),
          if (d.members.isEmpty)
            const AppSectionEmpty('暂无队员')
          else
            for (final m in d.members)
              Padding(
                padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
                child: _memberCard(context, m),
              ),
        ],
      );
    });
  }

  Widget _teamInfo(BuildContext context, Team team) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  team.name,
                  style: text.titleMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              AppStatusChip(
                label: team.isSigned ? '已报名' : '未报名',
                status: team.isSigned ? AppStatus.success : AppStatus.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spaceS),
          AppMetaRow(
            icon: Icons.military_tech_outlined,
            label: '队长',
            value: team.captainUsername,
          ),
          AppMetaRow(
            icon: Icons.groups_outlined,
            label: '在队人数',
            value: '${team.memberCount} 人',
          ),
          const SizedBox(height: AppDesign.spaceS),
          const Divider(height: 1),
          const SizedBox(height: AppDesign.spaceS),
          Text(
            team.description.isEmpty ? '暂无简介' : team.description,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _memberCard(BuildContext context, TeamMemberInfo m) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (roleLabel, roleStatus) = _roleBadge(m.type);
    return AppCard(
      child: Row(
        children: [
          ChatAvatar(
            userId: m.userId,
            name: m.username,
            hasAvatar: m.hasAvatar,
            avatarUpdatedAt: m.avatarUpdatedAt,
            radius: 20,
            onTap: () => Get.to(() => UserProfilePage(userId: m.userId)),
          ),
          const SizedBox(width: AppDesign.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.username,
                  style: text.titleSmall?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppDesign.spaceXXXS),
                Text(
                  'ID ${m.userId} · ${_joinedAtText(m.joinedAt)}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (roleStatus != null) AppStatusChip(label: roleLabel, status: roleStatus),
        ],
      ),
    );
  }
}
