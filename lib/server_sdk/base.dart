import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/local_media.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/comp.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class DCRequest {
  int time;
  String? userToken;
  Map<String, dynamic> data;

  DCRequest({required this.time, required this.userToken, required this.data});

  DCRequest.fromJson(UserObj user, this.data)
    : time = DateTime.now().millisecondsSinceEpoch,
      userToken = user.token ?? "";

  Map<String, dynamic> toJson() => {"send_time": time, "user": userToken ?? "", "data": data};

  @override
  String toString() => jsonEncode(toJson());
}

class DCResponse {
  int time;
  int code;
  Map<String, dynamic> data;

  /// The user token this request was sent with, so auth failures can be
  /// matched against the current session: a stale in-flight 404 from a
  /// previous token must not log the current one out.
  String? requestToken;

  DCResponse({required this.time, required this.code, required this.data, this.requestToken});

  DCResponse.fromJson(Map<String, dynamic> json, {this.requestToken})
    : time = json["time"] as int,
      code = json["code"] as int,
      data = json["data"] as Map<String, dynamic>;

  Map<String, dynamic> toJson() => {"send_time": time, "code": code, "data": data};

  @override
  String toString() => jsonEncode(toJson());
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}

/// Thrown when the server rejects the current token (missing, invalid or
/// expired). The client should clear the local session and go back to login.
/// [token] is the token the failed request was sent with.
class AuthExpiredException implements Exception {
  final String? token;

  AuthExpiredException([this.token]);
}

/// Result of a registration attempt.
enum RegisterResult { ok, exists }

/// Media type to declare for an avatar upload, derived from the file
/// extension.
///
/// `package:http` does **not** infer it from the path: multipart parts built
/// via [buildMediaPart] (`fromPath` on native, `fromBytes` on web) leave
/// `contentType` null unless it is passed explicitly, and the constructor
/// falls back to `application/octet-stream`, which the server's avatar MIME
/// allow-list rejects. Unknown extensions fall back to `image/jpeg`, matching
/// the server's behaviour of validating the extension separately.
MediaType avatarMediaType(String path) {
  final dot = path.lastIndexOf(".");
  final ext = dot < 0 ? "" : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    "png" => MediaType("image", "png"),
    "gif" => MediaType("image", "gif"),
    "webp" => MediaType("image", "webp"),
    _ => MediaType("image", "jpeg"),
  };
}

class SDK {
  /// 服务器地址不再由 SDK 自己持有：`--dart-define=SERVER_IP/SERVER_PORT`
  /// 只是出厂默认值，运行时可在设置界面改，最终都收敛到 [ServerSettings]。
  /// 这样 HTTP 与 WebSocket 永远指向同一处，不会出现改了一半的错配。
  static const Duration _requestTimeout = Duration(seconds: 10);

  static Uri _uri(String path) => Uri.parse("${ServerSettings.baseUrl}$path");

  /// 连通性探针：打一个无需登录的公开接口 `/api/comp/list_all`。
  ///
  /// 只要回包能解析出本项目信封且 `code == 200`，就说明地址可达、且确实是
  /// DebateCloud 服务端（而不是随便一个返回 HTML 的 Web 服务）。
  /// 超时、非 200、非 JSON 一律视为不可达。
  ///
  /// [baseUrl] 用于探测**尚未保存**的候选地址，缺省探测当前生效地址。
  static Future<bool> ping({String? baseUrl}) async {
    try {
      final res = await http
          .post(
            Uri.parse("${baseUrl ?? ServerSettings.baseUrl}/api/comp/list_all"),
            headers: {"Content-Type": "application/json"},
            body: DCRequest.fromJson(UserObj(token: null), {}).toString(),
          )
          .timeout(_requestTimeout);
      if (res.statusCode != 200) return false;
      final dcRes = DCResponse.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      );
      return dcRes.code == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<DCResponse> _post(String path, UserObj user, Map<String, dynamic> data) async {
    final res = await http.post(
      _uri(path),
      headers: {"Content-Type": "application/json"},
      body: DCRequest.fromJson(user, data).toString(),
    ).timeout(_requestTimeout);
    // The server returns application/json without a charset, so force UTF-8
    // decoding to keep Chinese text intact.
    return DCResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      requestToken: user.token,
    );
  }

  /// Login. Returns an anonymous UserObj when credentials are rejected.
  static Future<UserObj> login(String username, String password) async {
    final dcRes = await _post("/api/login", UserObj(token: null), {
      "username": username,
      "password": password,
    });
    return UserObj(token: dcRes.code == 404 ? null : dcRes.data["token"] as String);
  }

  /// Register a new account. The server does not return a token, so the
  /// caller is expected to log in afterwards.
  static Future<RegisterResult> register(String username, String password, String email) async {
    final dcRes = await _post("/api/register", UserObj(token: null), {
      "username": username,
      "password": password,
      "email": email,
    });
    if (dcRes.code != 200) {
      throw ApiException("Register failed (${dcRes.code})");
    }
    final status = (dcRes.data["status"] ?? "ok") as String;
    return status == "exists" ? RegisterResult.exists : RegisterResult.ok;
  }

  /// Verify the cached session is still accepted by the server. Throws
  /// [AuthExpiredException] when the token is missing or rejected.
  static Future<void> verifySession(UserObj user) async {
    if (user.isAnonymous) throw AuthExpiredException(user.token);
    final dcRes = await _post("/api/verify", user, {});
    if (dcRes.code != 200) throw AuthExpiredException(user.token);
  }

  /// Fetch the user profile.
  /// Null when logged out or the request fails; throws [AuthExpiredException]
  /// when the server rejects the current token.
  static Future<UserProfile?> fetchUserProfile(UserObj user) async {
    if (user.isAnonymous) return null;
    final dcRes = await _post("/api/profile", user, {});
    if (dcRes.code == 404) throw AuthExpiredException(user.token);
    if (dcRes.code != 200) return null;
    final d = dcRes.data;
    return UserProfile(
      userId: d["userId"] as int,
      username: (d["username"] ?? "") as String,
      nickname: (d["nickname"] ?? "") as String,
      bio: (d["bio"] ?? "") as String,
      email: (d["email"] ?? "") as String,
      createdAt: (d["createdAt"] ?? "") as String,
      updatedAt: (d["updatedAt"] ?? "") as String,
    );
  }

  /// Update profile fields. Only non-null fields are sent to the server.
  static Future<bool> updateProfile(UserObj user, {String? nickname, String? bio}) async {
    final dcRes = await _post("/api/upload_profile", user, {"nickname": ?nickname, "bio": ?bio});
    if (dcRes.code == 404) throw AuthExpiredException(user.token);
    return dcRes.code == 200;
  }

  /// 查看他人（或自己）的公开主页资料。目标不存在时抛
  /// [ApiException]（服务端 data 带 error，与登录态失效区分开）。
  static Future<PublicProfile> fetchPublicProfile(UserObj user, {required int userId}) async {
    final r = _authed(await _post("/api/user/profile", user, {"userId": userId}));
    return PublicProfile.fromJson(r.data["profile"] as Map<String, dynamic>);
  }

  /// Download the avatar image into the local cache.
  /// Null when the user has no avatar yet.
  static Future<CachedMedia?> fetchAvatar(UserObj user) async {
    if (user.isAnonymous) return null;
    final res = await http.post(
      _uri("/api/avatar/"),
      headers: {"Content-Type": "application/json"},
      body: DCRequest.fromJson(user, {}).toString(),
    ).timeout(_requestTimeout);
    // The avatar endpoint streams raw image bytes; anything else (non-200,
    // empty payload, or a JSON error body) means "no avatar available".
    final contentType = res.headers["content-type"] ?? "";
    if (res.statusCode != 200 || res.bodyBytes.isEmpty || contentType.contains("json")) {
      return null;
    }
    return writeCachedMedia("avatar", res.bodyBytes);
  }

  /// Upload a new avatar image (max 10MB server-side).
  ///
  /// The file part must carry an explicit image media type: without it the
  /// server rejects the upload as an unsupported file type.
  ///
  /// Throws [AuthExpiredException] when the token is rejected, and
  /// [ApiException] carrying the server's reason when the file itself is
  /// refused (unsupported format, too large, account cancelled, ...).
  static Future<void> uploadAvatar(UserObj user, XFile file) async {
    final req = http.MultipartRequest("POST", _uri("/api/upload_avatar"));
    req.fields["body"] = DCRequest.fromJson(user, {}).toString();
    req.files.add(
      await buildMediaPart("file", file, avatarMediaType(file.name)),
    );
    final res = await http.Response.fromStream(await req.send().timeout(_requestTimeout)).timeout(_requestTimeout);
    if (res.statusCode != 200) {
      throw ApiException("上传失败（HTTP ${res.statusCode}）");
    }
    final dcRes = DCResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    if (dcRes.code == 404) throw AuthExpiredException(user.token);
    if (dcRes.code != 200) {
      // 服务端把拒绝原因放在 data.error，没有时退回状态码。
      throw ApiException((dcRes.data["error"] as String?)?.trim().isNotEmpty == true
          ? dcRes.data["error"] as String
          : "上传失败（${dcRes.code}）");
    }
  }

  /// List all competitions, soonest start date first.
  static Future<List<Competition>> fetchCompetitions() async {
    final dcRes = await _post("/api/comp/list_all", UserObj(token: null), {});
    if (dcRes.code != 200) {
      throw ApiException("Failed to load competitions (${dcRes.code})");
    }
    final comps = <Competition>[
      for (final v in dcRes.data.values)
        if (v is Map<String, dynamic>) Competition.fromJson(v),
    ];
    comps.sort((a, b) {
      if (a.startDate == null) return 1;
      if (b.startDate == null) return -1;
      return a.startDate!.compareTo(b.startDate!);
    });
    return comps;
  }

  // ==================== 报名 / 队伍（需登录） ====================

  static Future<List<Team>> fetchMyTeams(UserObj user) async {
    final r = _authed(await _post("/api/comp/team/list", user, {}));
    return [
      for (final v in (r.data['teams'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) Team.fromJson(v),
    ];
  }

  /// 队伍详情（队员/赛事管理员/总管理员可查，服务端做权限校验）。
  static Future<TeamDetail> fetchTeamDetail(UserObj user, {required int teamId}) async {
    final r = _authed(await _post("/api/comp/team/detail", user, {"teamId": teamId}));
    return TeamDetail.fromJson(r.data);
  }

  static Future<int> createTeam(
    UserObj user, {
    required int competitionId,
    required String name,
    required String description,
  }) async {
    final r = _authed(
      await _post('/api/comp/team/create', user, {
        'competitionId': competitionId,
        'name': name,
        'description': description,
      }),
    );
    return (r.data['id'] as num?)?.toInt() ?? 0;
  }

  static Future<bool> updateTeam(
    UserObj user, {
    required int teamId,
    required String name,
    required String description,
  }) async {
    final r = _authed(
      await _post('/api/comp/team/update', user, {
        'teamId': teamId,
        'name': name,
        'description': description,
      }),
    );
    return r.data['pending'] == true;
  }

  static Future<Map<String, dynamic>> inviteMember(
    UserObj user, {
    required int teamId,
    required int targetUserId,
    int type = 1,
    String message = '',
  }) async {
    final r = _authed(
      await _post('/api/comp/team/member/invite', user, {
        'teamId': teamId,
        'targetUserId': targetUserId,
        'type': type,
        'message': message,
      }),
    );
    return r.data;
  }

  static Future<List<Invitation>> fetchMyInvitations(UserObj user) async {
    final r = _authed(await _post('/api/comp/invitation/list', user, {}));
    return [
      for (final v in (r.data['invitations'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) Invitation.fromJson(v),
    ];
  }

  static Future<void> respondInvitation(
    UserObj user, {
    required int invitationId,
    required bool accept,
  }) async {
    _authed(
      await _post('/api/comp/invitation/respond', user, {
        'invitationId': invitationId,
        'accept': accept,
      }),
    );
  }

  static Future<int> applySignup(UserObj user, {required int teamId}) async {
    final r = _authed(await _post('/api/comp/signup/apply', user, {'teamId': teamId}));
    return (r.data['signupId'] as num?)?.toInt() ?? 0;
  }

  static Future<List<SignupRecord>> fetchMySignups(UserObj user) async {
    final r = _authed(await _post('/api/comp/signup/my', user, {}));
    return [
      for (final v in (r.data['signups'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) SignupRecord.fromJson(v),
    ];
  }

  // ==================== 赛事管理员（客户端专属） ====================

  static Future<List<ManagerCompetition>> fetchManagerCompetitions(UserObj user) async {
    final r = _authed(await _post("/api/comp/manager/competitions", user, {}));
    return [
      for (final v in (r.data['competitions'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) ManagerCompetition.fromJson(v),
    ];
  }

  /// 某赛事的全部队伍（赛事管理员/总管理员）。
  static Future<List<Team>> fetchManagerTeams(UserObj user, {required int competitionId}) async {
    final r = _authed(
      await _post('/api/comp/manager/teams', user, {'competitionId': competitionId}),
    );
    return [
      for (final v in (r.data['teams'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) Team.fromJson(v),
    ];
  }

  static Future<List<SignupRecord>> fetchPendingSignups(
    UserObj user, {
    required int competitionId,
  }) async {
    final r = _authed(
      await _post('/api/comp/manager/signups', user, {'competitionId': competitionId}),
    );
    return [
      for (final v in (r.data['signups'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) SignupRecord.fromJson(v),
    ];
  }

  static Future<void> reviewSignup(
    UserObj user, {
    required int signupId,
    required bool approve,
    String remark = '',
  }) async {
    _authed(
      await _post('/api/comp/manager/signup/review', user, {
        'signupId': signupId,
        'approve': approve,
        'remark': remark,
      }),
    );
  }

  static Future<List<OperationRequest>> fetchPendingOperations(
    UserObj user, {
    required int competitionId,
  }) async {
    final r = _authed(
      await _post('/api/comp/manager/operation-requests', user, {
        'competitionId': competitionId,
      }),
    );
    return [
      for (final v in (r.data['requests'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) OperationRequest.fromJson(v),
    ];
  }

  static Future<void> reviewOperation(
    UserObj user, {
    required int requestId,
    required bool approve,
    String remark = '',
  }) async {
    _authed(
      await _post('/api/comp/manager/operation/review', user, {
        'requestId': requestId,
        'approve': approve,
        'remark': remark,
      }),
    );
  }

  /// 校验 200；404 且无 error 视为登录态失效。
  static DCResponse _authed(DCResponse r) {
    if (r.code == 404 && (r.data.isEmpty)) throw AuthExpiredException(r.requestToken);
    if (r.code != 200) {
      final message = (r.data['error'] ?? '操作失败（${r.code}）').toString();
      throw ApiException(message);
    }
    return r;
  }
}
