import 'package:debate_cloud/app/local_media.dart';

class UserObj {
  String? token;

  UserObj({required this.token});

  bool get isAnonymous => token == null || token!.isEmpty;
}

class UserProfile {
  int userId;
  String username;
  String nickname;
  String bio;
  String email;
  String createdAt;
  String updatedAt;

  /// 本地缓存的头像媒体（原生端指向缓存文件，Web 端持有内存字节）。
  CachedMedia? avatar;

  UserProfile({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.bio,
    required this.email,
    required this.createdAt,
    required this.updatedAt,
    this.avatar,
  });
}

/// 他人主页公开资料（服务端不下发 email）。
class PublicProfile {
  int userId;
  String username;
  String nickname;
  String bio;
  String createdAt;

  /// 与其他接口同源的头像版本，供 ChatAvatar 版本缓存复用。
  String avatarUpdatedAt;
  bool hasAvatar;

  /// 账号是否已注销；注销时 username 固定"注销用户"。
  bool cancelled;

  /// 目标是否为当前登录用户本人。
  bool isSelf;

  /// 查看者与目标的好友关系（口径同用户搜索接口）。
  bool isFriend;
  bool requestSent;

  PublicProfile({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.bio,
    required this.createdAt,
    required this.avatarUpdatedAt,
    required this.hasAvatar,
    required this.cancelled,
    required this.isSelf,
    required this.isFriend,
    required this.requestSent,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> j) => PublicProfile(
    userId: (j['userId'] as num?)?.toInt() ?? 0,
    username: (j['username'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    bio: (j['bio'] ?? '') as String,
    createdAt: (j['createdAt'] ?? '') as String,
    avatarUpdatedAt: (j['avatarUpdatedAt'] ?? '') as String,
    hasAvatar: j['hasAvatar'] == true,
    cancelled: j['cancelled'] == true,
    isSelf: j['isSelf'] == true,
    isFriend: j['isFriend'] == true,
    requestSent: j['requestSent'] == true,
  );

  String get displayName => nickname.isEmpty ? username : username;
}
