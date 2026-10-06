import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/navigation_service.dart';
import 'package:debate_cloud/routed_apps/competition/detail_controller.dart';
import 'package:debate_cloud/routed_apps/login/view.dart';
import 'package:debate_cloud/routed_apps/manager/comp_view.dart';
import 'package:debate_cloud/routed_apps/competition/team_detail_view.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class CompetitionDetailPage extends StatefulWidget {
  final Competition competition;

  const CompetitionDetailPage({super.key, required this.competition});

  @override
  State<CompetitionDetailPage> createState() => _CompetitionDetailPageState();
}

class _CompetitionDetailPageState extends State<CompetitionDetailPage> {
  late final CompetitionDetailController controller;

  @override
  void initState() {
    super.initState();
    controller = CompetitionDetailController(competition: widget.competition);
    Get.put(controller, tag: 'comp-detail-${widget.competition.id}');
  }

  @override
  void dispose() {
    Get.delete<CompetitionDetailController>(tag: 'comp-detail-${widget.competition.id}');
    super.dispose();
  }

  static String _fmtDate(DateTime? d) => d == null
      ? '待定'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static (String, AppStatus) _statusStyle(CompetitionStatus s) => switch (s) {
    CompetitionStatus.signupOpen => ('报名中', AppStatus.success),
    CompetitionStatus.ongoing => ('进行中', AppStatus.info),
    CompetitionStatus.upcoming => ('未开始', AppStatus.warning),
    CompetitionStatus.finished => ('已结束', AppStatus.neutral),
  };

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.authed) {
        return AppPageScaffold(
          title: '赛事详情',
          body: _guestView(context, controller),
        );
      }
      if (controller.isLoading.value &&
          controller.teams.isEmpty &&
          controller.signups.isEmpty) {
        return const AppPageScaffold(
          title: '赛事详情',
          loadingState: AppSkeletonList(itemCount: 4, showAvatar: false),
        );
      }
      return AppPageScaffold(
        title: '赛事详情',
        onRefresh: controller.load,
        children: [
          ResponsiveColumns(
            leftFlex: 3,
            rightFlex: 2,
            left: _compHeader(context, controller),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._teamSection(context, controller),
                if (controller.isManager.value) ...[
                  const SizedBox(height: AppDesign.spaceM),
                  FilledButton.icon(
                    onPressed: () => Get.to(
                      () => ManagerCompPage(competitionId: widget.competition.id),
                    ),
                    icon: const Icon(Icons.verified_user_outlined, size: 20),
                    label: const Text('赛事审批管理'),
                  ),
                ],
              ],
            ),
          ),
          if (controller.isManager.value)
            ..._allTeamsSection(context, controller),
        ],
      );
    });
  }

  Widget _guestView(BuildContext context, CompetitionDetailController c) {
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
                Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppDesign.spaceM),
                const Text('登录后即可创建队伍并报名'),
                const SizedBox(height: AppDesign.spaceL),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Get.find<NavigationService>().toGlobal(LoginView()),
                    child: const Text('去登录'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _compHeader(BuildContext context, CompetitionDetailController c) {
    final comp = c.competition;
    final policy = CompetitionPolicy.fromJsonDes(comp.jsonDes);
    final (statusLabel, status) = _statusStyle(comp.status);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  comp.name,
                  style: text.headlineSmall?.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: AppDesign.spaceXS),
              AppStatusChip(label: statusLabel, status: status),
            ],
          ),
          const SizedBox(height: AppDesign.spaceS),
          Text(
            comp.description.isEmpty ? '暂无简介' : comp.description,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppDesign.spaceM),
          const Divider(height: 1),
          const SizedBox(height: AppDesign.spaceS),
          AppMetaRow(
            icon: Icons.group_outlined,
            label: '报名人数',
            value: policy.rangeText,
          ),
          AppMetaRow(
            icon: Icons.event_outlined,
            label: '比赛时间',
            value: '${_fmtDate(comp.startDate)} ~ ${_fmtDate(comp.endDate)}',
          ),
          AppMetaRow(
            icon: Icons.how_to_reg_outlined,
            label: '报名时间',
            value:
                '${_fmtDate(comp.signupStartDate)} ~ ${_fmtDate(comp.signupEndDate)}',
          ),
          if (controller.errorMessage.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spaceS),
            Text(
              controller.errorMessage.value,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _teamSection(BuildContext context, CompetitionDetailController c) {
    final captain = c.captainTeam;
    final member = c.memberTeam;
    final mySignup = c.mySignup;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (captain == null && member == null) {
      return [
        AppEmptyState(
          icon: Icons.group_add_outlined,
          message: '尚未加入任何队伍\n创建队伍后你就是队长，可邀请队员并报名',
          actionLabel: '创建队伍',
          onAction: () => _createTeam(context, c),
          verticalPadding: AppDesign.spaceL,
        ),
      ];
    }
    final team = member!;
    final isCaptain = captain != null;
    return [
      AppCard(
        onTap: () => Get.to(() => TeamDetailPage(teamId: team.id, teamName: team.name)),
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
            if (!isCaptain) ...[
              const SizedBox(height: AppDesign.spaceS),
              Text(
                '你是队员，队伍操作由队长发起',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (mySignup != null) ...[
              const SizedBox(height: AppDesign.spaceXXS),
              AppMetaRow(
                icon: Icons.assignment_outlined,
                label: '报名状态',
                value: _signupLabel(mySignup.status),
              ),
            ],
            if (isCaptain) ...[
              const SizedBox(height: AppDesign.spaceM),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _editTeam(context, c, team),
                      child: const Text('编辑'),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spaceXS),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _invite(context, c, team),
                      child: const Text('邀请'),
                    ),
                  ),
                  const SizedBox(width: AppDesign.spaceXS),
                  Expanded(
                    child: FilledButton(
                      onPressed: team.isSigned || mySignup?.status == 0
                          ? null
                          : () => _apply(context, c, team),
                      child: const Text('报名'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// 赛事管理员视角：该赛事全部队伍列表，点击进入队伍详情。
  List<Widget> _allTeamsSection(BuildContext context, CompetitionDetailController c) {
    return [
      const SizedBox(height: AppDesign.spaceL),
      const AppSectionHeader(title: '全部队伍', icon: Icons.groups_outlined),
      const SizedBox(height: AppDesign.spaceS),
      if (c.allTeams.isEmpty)
        const AppSectionEmpty('该赛事暂无队伍')
      else
        AppResponsiveGrid(
          maxColumns: 2,
          children: [for (final t in c.allTeams) _allTeamCard(context, t)],
        ),
    ];
  }

  Widget _allTeamCard(BuildContext context, Team t) {
    return AppInfoCard(
      onTap: () => Get.to(() => TeamDetailPage(teamId: t.id, teamName: t.name)),
      title: t.name,
      status: t.isSigned ? AppStatus.success : AppStatus.neutral,
      statusLabel: t.isSigned ? '已报名' : '未报名',
      description: '队长 ${t.captainUsername} · 在队 ${t.memberCount} 人',
    );
  }

  Future<void> _createTeam(BuildContext context, CompetitionDetailController c) async {
    final values = await _promptStrings(
      context,
      title: '创建队伍',
      nameHint: '队伍名称',
      descHint: '队伍简介（可选）',
    );
    if (values == null) return;
    try {
      await c.createTeam(values.$1, values.$2);
      AppSnackbar.success('成功', '队伍已创建');
    } on AuthExpiredException catch (e) {
      await c.auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      AppSnackbar.error('创建失败', e.message);
    } catch (_) {
      AppSnackbar.error('创建失败', '请检查服务器连接');
    }
  }

  Future<void> _editTeam(
    BuildContext context,
    CompetitionDetailController c,
    Team team,
  ) async {
    final values = await _promptStrings(
      context,
      title: '编辑队伍',
      nameHint: '队伍名称',
      descHint: '队伍简介',
      nameInit: team.name,
      descInit: team.description,
    );
    if (values == null) return;
    try {
      final pending = await c.updateTeam(team, values.$1, values.$2);
      AppSnackbar.success('已提交', pending ? '队伍已报名，修改需赛事管理员审批后生效' : '队伍信息已更新');
    } on AuthExpiredException catch (e) {
      await c.auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      AppSnackbar.error('编辑失败', e.message);
    } catch (_) {
      AppSnackbar.error('编辑失败', '请检查服务器连接');
    }
  }

  Future<void> _invite(
    BuildContext context,
    CompetitionDetailController c,
    Team team,
  ) async {
    final userIdText = await _promptSingle(context, title: '邀请入队', hint: '被邀请人用户 ID');
    if (userIdText == null) return;
    final targetId = int.tryParse(userIdText);
    if (targetId == null || targetId <= 0) {
      AppSnackbar.show('提示', '请输入有效的用户 ID');
      return;
    }
    try {
      final res = await c.invite(team, targetId);
      AppSnackbar.success(
        '已发送',
        res['pending'] == true ? '队伍已报名，邀请需赛事管理员审批后才会发出' : '邀请已发出，等待对方接受',
      );
      await c.load();
    } on AuthExpiredException catch (e) {
      await c.auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      AppSnackbar.error('邀请失败', e.message);
    } catch (_) {
      AppSnackbar.error('邀请失败', '请检查服务器连接');
    }
  }

  Future<void> _apply(
    BuildContext context,
    CompetitionDetailController c,
    Team team,
  ) async {
    try {
      await c.applySignup(team);
      AppSnackbar.success('成功', '报名申请已提交，等待赛事管理员审核');
    } on AuthExpiredException catch (e) {
      await c.auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      AppSnackbar.error('报名失败', e.message);
    } catch (_) {
      AppSnackbar.error('报名失败', '请检查服务器连接');
    }
  }

  static String _signupLabel(int status) => switch (status) {
    0 => '待审核',
    1 => '已通过',
    2 => '已拒绝',
    _ => '未知',
  };

  static Future<(String, String)?> _promptStrings(
    BuildContext context, {
    required String title,
    required String nameHint,
    required String descHint,
    String nameInit = '',
    String descInit = '',
  }) async {
    final nameCtrl = TextEditingController(text: nameInit);
    final descCtrl = TextEditingController(text: descInit);
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: nameHint),
              autofocus: true,
            ),
            const SizedBox(height: AppDesign.spaceM),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(labelText: descHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, (nameCtrl.text.trim(), descCtrl.text.trim()));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result;
  }

  static Future<String?> _promptSingle(
    BuildContext context, {
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: title,
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
