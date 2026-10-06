import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:get/get.dart';

class HomeController extends GetxController {
  final competitions = <Competition>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final keyword = ''.obs;

  /// 状态筛选，null 表示「全部」。
  final statusFilter = Rxn<CompetitionStatus>();

  /// 宽屏双栏下右侧预览的赛事 id；窄屏不使用（点了直接进详情页）。
  final previewId = Rxn<int>();

  void selectPreview(Competition c) => previewId.value = c.id;

  @override
  void onInit() {
    super.onInit();
    fetchCompetitions();
  }

  /// 是否有任何筛选生效，用于空态区分「本来就没数据」和「被筛没了」。
  bool get hasFilter =>
      statusFilter.value != null || keyword.value.trim().isNotEmpty;

  List<Competition> get filtered {
    final k = keyword.value.trim();
    final status = statusFilter.value;
    return competitions.where((c) {
      if (status != null && c.status != status) return false;
      if (k.isEmpty) return true;
      return c.name.contains(k) || c.description.contains(k);
    }).toList();
  }

  void setStatusFilter(CompetitionStatus? status) =>
      statusFilter.value = status;

  Future<void> fetchCompetitions() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      competitions.value = await SDK.fetchCompetitions();
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接后重试';
    } finally {
      isLoading.value = false;
    }
  }
}
