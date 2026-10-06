import 'dart:convert';

/// Competition entity mirroring the server-side model.
class Competition {
  final int id;
  final String name;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? signupStartDate;
  final DateTime? signupEndDate;
  final String jsonDes;

  Competition({
    required this.id,
    required this.name,
    required this.description,
    this.startDate,
    this.endDate,
    this.signupStartDate,
    this.signupEndDate,
    required this.jsonDes,
  });

  factory Competition.fromJson(Map<String, dynamic> json) => Competition(
    id: json["id"] as int,
    name: (json["name"] ?? "") as String,
    description: (json["description"] ?? "") as String,
    startDate: _parseDate(json["startDate"]),
    endDate: _parseDate(json["endDate"]),
    signupStartDate: _parseDate(json["signupStartDate"]),
    signupEndDate: _parseDate(json["signupEndDate"]),
    jsonDes: (json["jsonDes"] ?? "") as String,
  );

  static DateTime? _parseDate(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

  /// Lifecycle status derived from the configured dates.
  CompetitionStatus get status {
    final now = DateTime.now();
    if (_within(now, signupStartDate, signupEndDate)) {
      return CompetitionStatus.signupOpen;
    }
    if (startDate != null && now.isBefore(startDate!)) {
      return CompetitionStatus.upcoming;
    }
    if (_within(now, startDate, endDate)) return CompetitionStatus.ongoing;
    if (endDate != null && now.isAfter(endDate!)) {
      return CompetitionStatus.finished;
    }
    return CompetitionStatus.upcoming;
  }

  static bool _within(DateTime now, DateTime? start, DateTime? end) =>
      start != null && end != null && !now.isBefore(start) && !now.isAfter(end);
}

enum CompetitionStatus { signupOpen, upcoming, ongoing, finished }

/// 赛事报名配置（json_des）。
class CompetitionPolicy {
  final int signupMin;
  final int? signupMax;

  CompetitionPolicy({this.signupMin = 4, this.signupMax});

  factory CompetitionPolicy.fromJsonDes(String? jsonDes) {
    if (jsonDes == null || jsonDes.trim().isEmpty) {
      return CompetitionPolicy();
    }
    try {
      final root = jsonDecode(jsonDes) as Map<String, dynamic>;
      final range = root['signupTeamMemberRange'] as Map<String, dynamic>?;
      final min = (range?['min'] as num?)?.toInt() ?? 4;
      final maxRaw = range?['max'];
      return CompetitionPolicy(
        signupMin: min,
        signupMax: maxRaw is num ? maxRaw.toInt() : null,
      );
    } catch (_) {
      return CompetitionPolicy();
    }
  }

  String get rangeText {
    final max = signupMax;
    return max == null ? '$signupMin 人及以上' : '$signupMin~$max 人';
  }

  bool inRange(int memberCount) {
    if (memberCount < signupMin) return false;
    final max = signupMax;
    return max == null || memberCount <= max;
  }
}

/// 队伍（与后端 teams 表对齐）。
class Team {
  final int id;
  final int competitionId;
  final String name;
  final int captainId;
  final String captainUsername;
  final String description;
  final int memberCount;
  final int status; // 0=未报名 1=已报名

  Team({
    required this.id,
    required this.competitionId,
    required this.name,
    required this.captainId,
    required this.captainUsername,
    required this.description,
    required this.memberCount,
    required this.status,
  });

  bool get isSigned => status == 1;

  factory Team.fromJson(Map<String, dynamic> json) => Team(
    id: (json['id'] as num?)?.toInt() ?? 0,
    competitionId: (json['competitionId'] as num?)?.toInt() ?? 0,
    name: (json['name'] ?? '') as String,
    captainId: (json['captainId'] as num?)?.toInt() ?? 0,
    captainUsername: (json['captainUsername'] ?? '') as String,
    description: (json['description'] ?? '') as String,
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    status: (json['status'] as num?)?.toInt() ?? 0,
  );
}

/// 队伍成员（队伍详情用，与后端 team_members 行对齐）。
class TeamMemberInfo {
  final int userId;
  final String username;
  final int type; // 0=队员 1=队长 2=教练
  final String joinedAt;
  final bool hasAvatar;

  /// 头像版本（user_profiles.updated_at），变化时客户端重新拉取头像。
  final String avatarUpdatedAt;

  TeamMemberInfo({
    required this.userId,
    required this.username,
    required this.type,
    required this.joinedAt,
    required this.hasAvatar,
    required this.avatarUpdatedAt,
  });

  bool get isCaptain => type == 1;
  bool get isCoach => type == 2;

  factory TeamMemberInfo.fromJson(Map<String, dynamic> json) => TeamMemberInfo(
    userId: (json['userId'] as num?)?.toInt() ?? 0,
    username: (json['username'] ?? '') as String,
    type: (json['type'] as num?)?.toInt() ?? 0,
    joinedAt: (json['joinedAt'] ?? '') as String,
    hasAvatar: json['hasAvatar'] == true,
    avatarUpdatedAt: (json['avatarUpdatedAt'] ?? '') as String,
  );
}

/// 队伍详情（后端 data 为队伍字段 + members，扁平结构）。
class TeamDetail {
  final Team team;
  final List<TeamMemberInfo> members;

  TeamDetail({required this.team, required this.members});

  factory TeamDetail.fromJson(Map<String, dynamic> json) => TeamDetail(
    team: Team.fromJson(json),
    members: [
      for (final v in (json['members'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) TeamMemberInfo.fromJson(v),
    ],
  );
}

/// 入队邀请。
class Invitation {
  final int id;
  final int teamId;
  final String teamName;
  final int competitionId;
  final String competitionName;
  final String inviterUsername;
  final int type; // 1=队员 2=教练
  final int status; // 0=待处理 1=接受 2=拒绝
  final String message;

  Invitation({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.competitionId,
    required this.competitionName,
    required this.inviterUsername,
    required this.type,
    required this.status,
    required this.message,
  });

  bool get isPending => status == 0;

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
    id: (json['id'] as num?)?.toInt() ?? 0,
    teamId: (json['teamId'] as num?)?.toInt() ?? 0,
    teamName: (json['teamName'] ?? '') as String,
    competitionId: (json['competitionId'] as num?)?.toInt() ?? 0,
    competitionName: (json['competitionName'] ?? '') as String,
    inviterUsername: (json['inviterUsername'] ?? '') as String,
    type: (json['type'] as num?)?.toInt() ?? 1,
    status: (json['status'] as num?)?.toInt() ?? 0,
    message: (json['message'] ?? '') as String,
  );
}

/// 报名记录。
class SignupRecord {
  final int id;
  final int competitionId;
  final int teamId;
  final String teamName;
  final int status; // 0=待审 1=通过 2=拒绝
  final String remark;
  final String appliedAt;
  final String competitionName;
  final int? memberCount;

  SignupRecord({
    required this.id,
    required this.competitionId,
    required this.teamId,
    required this.teamName,
    required this.status,
    required this.remark,
    required this.appliedAt,
    required this.competitionName,
    this.memberCount,
  });

  factory SignupRecord.fromJson(Map<String, dynamic> json) => SignupRecord(
    id: (json['id'] as num?)?.toInt() ?? 0,
    competitionId: (json['competitionId'] as num?)?.toInt() ?? 0,
    teamId: (json['teamId'] as num?)?.toInt() ?? 0,
    teamName: (json['teamName'] ?? '') as String,
    status: (json['status'] as num?)?.toInt() ?? 0,
    remark: (json['remark'] ?? '') as String,
    appliedAt: (json['appliedAt'] ?? '') as String,
    competitionName: (json['competitionName'] ?? '') as String,
    memberCount: (json['memberCount'] as num?)?.toInt(),
  );
}

/// 已报名队伍的操作审批记录。
class OperationRequest {
  final int id;
  final int teamId;
  final String teamName;
  final int type; // 1=编辑队伍 2=发送邀请
  final int status;
  final String requesterUsername;
  final String requestedAt;
  final String remark;
  final Map<String, dynamic> payload;

  OperationRequest({
    required this.id,
    required this.teamId,
    required this.teamName,
    required this.type,
    required this.status,
    required this.requesterUsername,
    required this.requestedAt,
    required this.remark,
    required this.payload,
  });

  factory OperationRequest.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> payload = {};
    try {
      final raw = (json['payloadJson'] ?? '{}') as String;
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    return OperationRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      teamId: (json['teamId'] as num?)?.toInt() ?? 0,
      teamName: (json['teamName'] ?? '') as String,
      type: (json['type'] as num?)?.toInt() ?? 1,
      status: (json['status'] as num?)?.toInt() ?? 0,
      requesterUsername: (json['requesterUsername'] ?? '') as String,
      requestedAt: (json['requestedAt'] ?? '') as String,
      remark: (json['remark'] ?? '') as String,
      payload: payload,
    );
  }
}

/// 赛事管理员可见的赛事及待办数量。
class ManagerCompetition {
  final int id;
  final String name;
  final int pendingSignups;
  final int pendingOperations;

  ManagerCompetition({
    required this.id,
    required this.name,
    required this.pendingSignups,
    required this.pendingOperations,
  });

  factory ManagerCompetition.fromJson(Map<String, dynamic> json) =>
      ManagerCompetition(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '') as String,
        pendingSignups: (json['pendingSignups'] as num?)?.toInt() ?? 0,
        pendingOperations: (json['pendingOperations'] as num?)?.toInt() ?? 0,
      );
}
