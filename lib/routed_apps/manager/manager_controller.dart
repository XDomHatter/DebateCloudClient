import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:get/get.dart';

class ManagerHomeController extends GetxController {
  final auth = Get.find<AuthService>();
  final competitions = <ManagerCompetition>[].obs;
  final isLoading = false.obs;
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
      competitions.value = await SDK.fetchManagerCompetitions(auth.userObj.value);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }
}

class ManagerCompController extends GetxController {
  final auth = Get.find<AuthService>();
  final int competitionId;
  final String competitionName;

  final signups = <SignupRecord>[].obs;
  final operations = <OperationRequest>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  ManagerCompController({required this.competitionId, required this.competitionName});

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final results = await Future.wait([
        SDK.fetchPendingSignups(auth.userObj.value, competitionId: competitionId),
        SDK.fetchPendingOperations(auth.userObj.value, competitionId: competitionId),
      ]);
      signups.value = results[0] as List<SignupRecord>;
      operations.value = results[1] as List<OperationRequest>;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> reviewSignup(SignupRecord s, bool approve, String remark) async {
    await SDK.reviewSignup(
      auth.userObj.value,
      signupId: s.id,
      approve: approve,
      remark: remark,
    );
    await load();
  }

  Future<void> reviewOperation(OperationRequest o, bool approve, String remark) async {
    await SDK.reviewOperation(
      auth.userObj.value,
      requestId: o.id,
      approve: approve,
      remark: remark,
    );
    await load();
  }
}
