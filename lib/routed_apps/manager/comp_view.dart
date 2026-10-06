import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/routed_apps/competition/team_detail_view.dart';
import 'package:debate_cloud/routed_apps/manager/manager_controller.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class ManagerCompPage extends StatefulWidget {
  final int competitionId;
  final String? competitionName;

  const ManagerCompPage({
    super.key,
    required this.competitionId,
    this.competitionName,
  });

  @override
  State<ManagerCompPage> createState() => _ManagerCompPageState();
}

class _ManagerCompPageState extends State<ManagerCompPage> {
  late final ManagerCompController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      ManagerCompController(
        competitionId: widget.competitionId,
        competitionName: widget.competitionName ?? '',
      ),
      tag: 'manager-comp-${widget.competitionId}',
    );
  }

  @override
  void dispose() {
    Get.delete<ManagerCompController>(tag: 'manager-comp-${widget.competitionId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value &&
          controller.signups.isEmpty &&
          controller.operations.isEmpty) {
        return AppPageScaffold(
          title: controller.competitionName,
          loadingState: const AppSkeletonList(itemCount: 4, showAvatar: false),
        );
      }
      return AppPageScaffold(
        title: controller.competitionName,
        onRefresh: controller.load,
        children: [
          const AppSectionHeader(
            title: '待审核报名',
            icon: Icons.how_to_reg_outlined,
          ),
          const SizedBox(height: AppDesign.spaceS),
          if (controller.signups.isEmpty)
            const AppSectionEmpty('暂无')
          else
            ResponsiveLayout(
              compact: Column(
                children: [
                  for (final s in controller.signups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
                      child: _signupCard(context, controller, s),
                    ),
                ],
              ),
              medium: AppResponsiveGrid(
                maxColumns: 2,
                children: [
                  for (final s in controller.signups)
                    _signupCard(context, controller, s),
                ],
              ),
              expanded: AppResponsiveGrid(
                maxColumns: 2,
                children: [
                  for (final s in controller.signups)
                    _signupCard(context, controller, s),
                ],
              ),
            ),
          const SizedBox(height: AppDesign.spaceL),
          const Divider(height: 1),
          const SizedBox(height: AppDesign.spaceM),
          const AppSectionHeader(
            title: '待审批队伍操作',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: AppDesign.spaceS),
          if (controller.operations.isEmpty)
            const AppSectionEmpty('暂无')
          else
            ResponsiveLayout(
              compact: Column(
                children: [
                  for (final o in controller.operations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
                      child: _opCard(context, controller, o),
                    ),
                ],
              ),
              medium: AppResponsiveGrid(
                maxColumns: 2,
                children: [
                  for (final o in controller.operations)
                    _opCard(context, controller, o),
                ],
              ),
              expanded: AppResponsiveGrid(
                maxColumns: 2,
                children: [
                  for (final o in controller.operations)
                    _opCard(context, controller, o),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _signupCard(BuildContext context, ManagerCompController c, SignupRecord s) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.teamName}（ID ${s.teamId}）',
            style: text.titleSmall?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppDesign.spaceS),
          AppMetaRow(
            icon: Icons.groups_outlined,
            label: '在队人数',
            value: '${s.memberCount ?? '-'}',
          ),
          AppMetaRow(
            icon: Icons.schedule_outlined,
            label: '申请时间',
            value: s.appliedAt,
          ),
          const SizedBox(height: AppDesign.spaceS),
          // 按钮主题的 minimumSize 宽度为无穷大，Row 主轴不约束子项，
          // 裸按钮会推出非法约束；用 Expanded 提供有界宽度。
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Get.to(
                    () => TeamDetailPage(teamId: s.teamId, teamName: s.teamName),
                  ),
                  child: const Text('查看队伍'),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _doReview(
                    context,
                    c,
                    '拒绝报名 ${s.teamName}',
                    false,
                    (r) => c.reviewSignup(s, false, r),
                  ),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: FilledButton(
                  onPressed: () => _doReview(
                    context,
                    c,
                    '通过报名 ${s.teamName}',
                    true,
                    (r) => c.reviewSignup(s, true, r),
                  ),
                  child: const Text('通过'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opCard(BuildContext context, ManagerCompController c, OperationRequest o) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final typeText = o.type == 1 ? '编辑队伍' : '发送邀请';
    final desc = o.type == 1
        ? '名称：${o.payload['name']}'
        : '邀请用户 ID ${o.payload['targetUserId']}（${o.payload['type'] == 2 ? '教练' : '队员'}）';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${o.teamName} · $typeText',
                  style: text.titleSmall?.copyWith(color: scheme.onSurface),
                ),
              ),
              AppStatusChip(label: typeText, status: AppStatus.info),
            ],
          ),
          const SizedBox(height: AppDesign.spaceS),
          AppMetaRow(
            icon: Icons.person_outline,
            label: '申请人',
            value: o.requesterUsername,
          ),
          AppMetaRow(icon: Icons.info_outline, label: '内容', value: desc),
          const SizedBox(height: AppDesign.spaceS),
          // 同上：裸按钮在 Row 中会因主题 minimumSize 宽度无穷大而崩坏。
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Get.to(
                    () => TeamDetailPage(teamId: o.teamId, teamName: o.teamName),
                  ),
                  child: const Text('查看队伍'),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _doReview(
                    context,
                    c,
                    '拒绝操作 ${o.teamName}',
                    false,
                    (r) => c.reviewOperation(o, false, r),
                  ),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              Expanded(
                child: FilledButton(
                  onPressed: () => _doReview(
                    context,
                    c,
                    '同意操作 ${o.teamName}',
                    true,
                    (r) => c.reviewOperation(o, true, r),
                  ),
                  child: const Text('同意'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _doReview(
    BuildContext context,
    ManagerCompController c,
    String title,
    bool approve,
    Future<void> Function(String remark) action,
  ) async {
    final ctrl = TextEditingController();
    final remark = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '备注（可选）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (remark == null) return;
    try {
      await action(remark);
      AppSnackbar.success('成功', approve ? '已同意' : '已拒绝');
    } on ApiException catch (e) {
      AppSnackbar.error('操作失败', e.message);
    } catch (_) {
      AppSnackbar.error('操作失败', '请检查服务器连接');
    }
  }
}
