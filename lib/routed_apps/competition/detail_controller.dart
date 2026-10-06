import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:get/get.dart';

class CompetitionDetailController extends GetxController {
  final Competition competition;
  final auth = Get.find<AuthService>();

  final teams = <Team>[].obs;
  final signups = <SignupRecord>[].obs;
  final isLoading = false.obs;
  final isManager = false.obs;
  final errorMessage = ''.obs;

  /// 赛事管理员视角下该赛事的全部队伍。
  final allTeams = <Team>[].obs;

  CompetitionDetailController({required this.competition});

  bool get authed => auth.isLoggedIn;

  /// 当前用户在该赛事中担任队长的队伍。
  Team? get captainTeam {
    final myId = auth.userProfile.value?.userId;
    if (myId == null) return null;
    for (final t in teams) {
      if (t.competitionId == competition.id && t.captainId == myId) {
        return t;
      }
    }
    return null;
  }

  /// 当前用户所属（含非队长）的队伍。
  Team? get memberTeam {
    for (final t in teams) {
      if (t.competitionId == competition.id) return t;
    }
    return null;
  }

  SignupRecord? get mySignup {
    final team = memberTeam;
    if (team == null) return null;
    for (final s in signups) {
      if (s.teamId == team.id) return s;
    }
    return null;
  }

  @override
  void onInit() {
    super.onInit();
    if (authed) load();
  }

  Future<void> load() async {
    if (!authed) return;
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final results = await Future.wait([
        SDK.fetchMyTeams(auth.userObj.value),
        SDK.fetchMySignups(auth.userObj.value),
        SDK.fetchManagerCompetitions(auth.userObj.value),
      ]);
      teams.value = results[0] as List<Team>;
      signups.value = results[1] as List<SignupRecord>;
      isManager.value = (results[2] as List<ManagerCompetition>)
          .any((m) => m.id == competition.id);
      if (isManager.value) {
        allTeams.value = await SDK.fetchManagerTeams(
          auth.userObj.value,
          competitionId: competition.id,
        );
      } else {
        allTeams.value = [];
      }
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      errorMessage.value = '加载失败，请稍后重试';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> createTeam(String name, String description) async {
    await SDK.createTeam(
      auth.userObj.value,
      competitionId: competition.id,
      name: name,
      description: description,
    );
    await load();
  }

  Future<bool> updateTeam(Team team, String name, String description) async {
    final pending = await SDK.updateTeam(
      auth.userObj.value,
      teamId: team.id,
      name: name,
      description: description,
    );
    await load();
    return pending;
  }

  Future<Map<String, dynamic>> invite(Team team, int targetUserId,
      {int type = 1, String message = ''}) {
    return SDK.inviteMember(
      auth.userObj.value,
      teamId: team.id,
      targetUserId: targetUserId,
      type: type,
      message: message,
    );
  }

  Future<void> applySignup(Team team) async {
    await SDK.applySignup(auth.userObj.value, teamId: team.id);
    await load();
  }
}
