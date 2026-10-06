import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/models/home/controller.dart';
import 'package:debate_cloud/routed_apps/competition/detail_view.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/widgets/app_page_scaffold.dart';
import 'package:debate_cloud/widgets/app_tooltip.dart';
import 'package:debate_cloud/widgets/app_widgets.dart';
import 'package:debate_cloud/widgets/responsive.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeView extends StatelessWidget {
  HomeView({super.key});

  final controller = Get.put(HomeController());

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
    // 下拉刷新不放脚手架上：双栏模式下主体是 Row（不可滚动），
    // 由各分支自己按需包 RefreshIndicator。
    return AppPageScaffold(
      title: '赛事中心',
      actions: [
        AppTooltip(
          message: '刷新',
          child: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.fetchCompetitions,
          ),
        ),
      ],
      header: _buildHeader(context),
      body: Obx(() {
        // 首屏用骨架屏：版式先成型，数据到达时不整页跳动。
        if (controller.isLoading.value && controller.competitions.isEmpty) {
          return _buildSkeleton(context);
        }
        if (controller.errorMessage.isNotEmpty && controller.competitions.isEmpty) {
          return _buildScrollable(
            AppEmptyState(
              icon: Icons.wifi_off_outlined,
              title: '加载失败',
              message: controller.errorMessage.value,
              hint: '确认服务器已启动、地址正确后重试（可在右上角修改）',
              actionLabel: '重试',
              onAction: controller.fetchCompetitions,
            ),
          );
        }
        final comps = controller.filtered;
        if (comps.isEmpty) {
          return _buildScrollable(
            AppEmptyState(
              icon: controller.hasFilter
                  ? Icons.filter_alt_outlined
                  : Icons.event_busy_outlined,
              title: controller.hasFilter ? '没有匹配的赛事' : '暂无赛事',
              message: controller.hasFilter
                  ? '换个关键词，或把状态筛选切回「全部」'
                  : '赛事创建后会显示在这里',
              verticalPadding: AppDesign.spaceXXL,
            ),
          );
        }
        return _buildContent(context, comps);
      }),
    );
  }

  /// 固定头部：搜索框 + 状态筛选条。两者宽度由脚手架统一限宽居中。
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesign.spaceM,
        AppDesign.spaceS,
        AppDesign.spaceM,
        AppDesign.spaceXXS,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索赛事名称或简介',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => controller.keyword.value = v,
          ),
          _buildFilterBar(context),
        ],
      ),
    );
  }

  /// 按可用宽度分叉：够宽就左列表 + 右预览，否则退回单栏列表 / 网格。
  Widget _buildContent(BuildContext context, List<Competition> comps) {
    // 选中项必须在这里解析：LayoutBuilder 的 builder 是在 **layout 阶段**跑的，
    // 在那里读 previewId 不会被 Obx 订阅（GetX 只在 build 阶段收集依赖），
    // 结果就是点了列表项右侧预览不刷新，要等别的重建才跟上。
    final selected = _previewOf(comps);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppDesign.bpTwoPane) {
          return ResponsiveLayout(
            compact: _buildList(comps),
            medium: _buildGrid(comps, maxColumns: 2),
            expanded: _buildGrid(comps, maxColumns: 3),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: AppDesign.twoPaneListWidth,
              child: _buildPreviewList(context, comps, selected),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: context.appBorderColor,
            ),
            Expanded(child: _buildPreviewPane(context, selected)),
          ],
        );
      },
    );
  }

  /// 当前预览项：优先用已选中的；被筛掉或还没选过就退回第一条。
  Competition? _previewOf(List<Competition> comps) {
    final id = controller.previewId.value;
    for (final c in comps) {
      if (c.id == id) return c;
    }
    return comps.isEmpty ? null : comps.first;
  }

  /// 双栏左栏：单列列表，点击只切换右侧预览，不再整页跳转。
  Widget _buildPreviewList(
    BuildContext context,
    List<Competition> comps,
    Competition? selected,
  ) {
    return RefreshIndicator(
      onRefresh: controller.fetchCompetitions,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        itemCount: comps.length,
        itemBuilder: (context, i) {
          final comp = comps[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
            child: _buildCompCard(
              context,
              comp,
              selected: comp.id == selected?.id,
              onTap: () => controller.selectPreview(comp),
            ),
          );
        },
      ),
    );
  }

  /// 双栏右栏：赛事预览 + 「查看详情」入口。
  Widget _buildPreviewPane(BuildContext context, Competition? comp) {
    if (comp == null) {
      return const AppEmptyState(
        icon: Icons.event_busy_outlined,
        title: '暂无赛事',
        message: '赛事创建后会显示在这里',
        verticalPadding: AppDesign.spaceXXL,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (label, status) = _statusStyle(comp.status);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesign.spaceM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  comp.name,
                  style: text.headlineSmall?.copyWith(color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: AppDesign.spaceS),
              AppStatusChip(label: label, status: status),
            ],
          ),
          if (comp.description.isNotEmpty) ...[
            const SizedBox(height: AppDesign.spaceS),
            Text(
              comp.description,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: AppDesign.spaceL),
          AppPanel(
            child: Column(
              children: [
                AppMetaRow(
                  icon: Icons.event_outlined,
                  label: '比赛',
                  value: '${_fmtDate(comp.startDate)} ~ ${_fmtDate(comp.endDate)}',
                ),
                AppMetaRow(
                  icon: Icons.how_to_reg_outlined,
                  label: '报名',
                  value:
                      '${_fmtDate(comp.signupStartDate)} ~ ${_fmtDate(comp.signupEndDate)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDesign.spaceL),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  Get.to(() => CompetitionDetailPage(competition: comp)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('查看详情'),
            ),
          ),
        ],
      ),
    );
  }

  /// 状态筛选条：全部 / 报名中 / 进行中 / 未开始 / 已结束。
  ///
  /// 与搜索框是「与」关系，两者任一生效都算筛选中（见 `hasFilter`）。
  Widget _buildFilterBar(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Obx(
        () => ListView(
          scrollDirection: Axis.horizontal,
          // 左右留白由 [_buildHeader] 统一给，这里再加会把 chips 推到 32。
          children: [
            for (final entry in _filterEntries)
              Padding(
                padding: const EdgeInsets.only(right: AppDesign.spaceXS),
                child: FilterChip(
                  label: Text(entry.$1),
                  selected: controller.statusFilter.value == entry.$2,
                  // 「全部」用 null 表示，FilterChip 的 selected 判等天然命中。
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => controller.setStatusFilter(entry.$2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<(String, CompetitionStatus?)> _filterEntries = [
    ('全部', null),
    ('报名中', CompetitionStatus.signupOpen),
    ('进行中', CompetitionStatus.ongoing),
    ('未开始', CompetitionStatus.upcoming),
    ('已结束', CompetitionStatus.finished),
  ];

  /// 首屏骨架：跟随当前断点摆出与真实内容一致的版式。
  Widget _buildSkeleton(BuildContext context) {
    Widget grid(int maxColumns) => AppResponsiveGrid(
      maxColumns: maxColumns,
      children: [
        for (var i = 0; i < 6; i++)
          const SizedBox(
            height: 168,
            child: AppSkeleton(radius: AppDesign.radiusL),
          ),
      ],
    );

    // 限宽与内边距由 AppPageScaffold 统一给。
    return ResponsiveLayout(
      compact: const AppSkeletonList(itemCount: 6, showAvatar: false),
      medium: grid(2),
      expanded: grid(3),
    );
  }

  /// 手机：单列列表，卡片高度自适应。
  Widget _buildList(List<Competition> comps) {
    return RefreshIndicator(
      onRefresh: controller.fetchCompetitions,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppDesign.spaceM),
        itemCount: comps.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: AppDesign.spaceS),
          child: _buildCompCard(context, comps[i]),
        ),
      ),
    );
  }

  /// 平板 / 桌面：等宽卡片网格。限宽由 [AppPageScaffold] 统一给。
  Widget _buildGrid(List<Competition> comps, {required int maxColumns}) {
    return RefreshIndicator(
      onRefresh: controller.fetchCompetitions,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppDesign.spaceM),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: maxColumns,
                mainAxisSpacing: AppDesign.spaceS,
                crossAxisSpacing: AppDesign.spaceS,
                mainAxisExtent: 168,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _buildCompCard(context, comps[i]),
                childCount: comps.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 空态 / 错误态也需要可滚动，保证下拉刷新可用。
  Widget _buildScrollable(Widget child) {
    return RefreshIndicator(
      onRefresh: controller.fetchCompetitions,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  /// [onTap] 默认直接进详情页；双栏模式下由调用方改成「切换右侧预览」。
  Widget _buildCompCard(
    BuildContext context,
    Competition comp, {
    bool selected = false,
    VoidCallback? onTap,
  }) {
    final (label, status) = _statusStyle(comp.status);
    return AppInfoCard(
      large: true,
      accentColor: context.statusStyleOf(status).foreground,
      selected: selected,
      onTap: onTap ?? () => Get.to(() => CompetitionDetailPage(competition: comp)),
      title: comp.name,
      status: status,
      statusLabel: label,
      description: comp.description,
      meta: [
        AppMetaRow(
          icon: Icons.event_outlined,
          label: '比赛',
          value: '${_fmtDate(comp.startDate)} ~ ${_fmtDate(comp.endDate)}',
        ),
        AppMetaRow(
          icon: Icons.how_to_reg_outlined,
          label: '报名',
          value:
              '${_fmtDate(comp.signupStartDate)} ~ ${_fmtDate(comp.signupEndDate)}',
        ),
      ],
    );
  }
}
