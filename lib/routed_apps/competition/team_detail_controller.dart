import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:get/get.dart';

class TeamDetailController extends GetxController {
  final int teamId;
  final auth = Get.find<AuthService>();

  final detail = Rxn<TeamDetail>();
  final isLoading = true.obs;
  final errorMessage = ''.obs;

  TeamDetailController({required this.teamId});

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      detail.value = await SDK.fetchTeamDetail(auth.userObj.value, teamId: teamId);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }
}
