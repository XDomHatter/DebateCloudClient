import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:get/get.dart';

class MyCompetitionsController extends GetxController {
  final auth = Get.find<AuthService>();
  final teams = <Team>[].obs;
  final signups = <SignupRecord>[].obs;
  final invitations = <Invitation>[].obs;
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
      final results = await Future.wait([
        SDK.fetchMyTeams(auth.userObj.value),
        SDK.fetchMySignups(auth.userObj.value),
        SDK.fetchMyInvitations(auth.userObj.value),
      ]);
      teams.value = results[0] as List<Team>;
      signups.value = results[1] as List<SignupRecord>;
      invitations.value = results[2] as List<Invitation>;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> respond(Invitation invitation, bool accept) async {
    await SDK.respondInvitation(
      auth.userObj.value,
      invitationId: invitation.id,
      accept: accept,
    );
    await load();
  }
}
