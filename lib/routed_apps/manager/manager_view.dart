import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/routed_apps/manager/comp_view.dart';
import 'package:debate_cloud/routed_apps/manager/manager_controller.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ManagerHomePage extends StatefulWidget {
  const ManagerHomePage({super.key});

  @override
  State<ManagerHomePage> createState() => _ManagerHomePageState();
}

class _ManagerHomePageState extends State<ManagerHomePage> {
  late final ManagerHomeController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(ManagerHomeController());
  }

  @override
  void dispose() {
    Get.delete<ManagerHomeController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value && controller.competitions.isEmpty) {
        return const AppPageScaffold(
          title: '赛事审批',
          loadingState: AppSkeletonList(itemCount: 4, showAvatar: false),
        );
      }
      // 空态 / 错误态也走 children：内容可滚动，下拉刷新同样可用
      // （此前这两个状态是死的，只能点「重试」按钮）。
      if (controller.errorMessage.isNotEmpty && controller.competitions.isEmpty) {
        return AppPageScaffold(
          title: '赛事审批',
          onRefresh: controller.load,
          children: [
            AppEmptyState(
              icon: Icons.wifi_off_outlined,
              title: '加载失败',
              message: controller.errorMessage.value,
              actionLabel: '重试',
              onAction: controller.load,
            ),
          ],
        );
      }
      final comps = controller.competitions;
      if (comps.isEmpty) {
        return AppPageScaffold(
          title: '赛事审批',
          onRefresh: controller.load,
          children: const [
            AppEmptyState(
              icon: Icons.inbox_outlined,
              title: '暂无待审批赛事',
              message: '你被指定为赛事管理员后，这里会列出需要处理的报名与操作',
            ),
          ],
        );
      }
      return AppPageScaffold(
        title: '赛事审批',
        onRefresh: controller.load,
        children: [
          const AppSectionHeader(
            title: '待处理赛事',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: AppDesign.spaceS),
          ResponsiveLayout(
            compact: Column(
              children: [
                for (final c in comps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
                    child: _compCard(context, c),
                  ),
              ],
            ),
            medium: AppResponsiveGrid(
              maxColumns: 2,
              children: [for (final c in comps) _compCard(context, c)],
            ),
            expanded: AppResponsiveGrid(
              maxColumns: 3,
              children: [for (final c in comps) _compCard(context, c)],
            ),
          ),
        ],
      );
    });
  }

  Widget _compCard(BuildContext context, ManagerCompetition c) {
    return AppInfoCard(
      onTap: () => Get.to(
        () => ManagerCompPage(
          competitionId: c.id,
          competitionName: c.name,
        ),
      ),
      title: c.name,
      chips: [
        if (c.pendingSignups > 0)
          AppStatusChip(
            label: '待审报名 ${c.pendingSignups}',
            status: AppStatus.warning,
          ),
        if (c.pendingOperations > 0)
          AppStatusChip(
            label: '待审批操作 ${c.pendingOperations}',
            status: AppStatus.info,
          ),
        if (c.pendingSignups == 0 && c.pendingOperations == 0)
          AppStatusChip(label: '已处理完', status: AppStatus.neutral),
      ],
    );
  }
}
