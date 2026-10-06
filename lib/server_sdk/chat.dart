import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/app/local_media.dart';
import 'package:debate_cloud/app/server_settings.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ==================== 数据模型 ====================

/// 搜索结果中的用户摘要。
class ChatUserBrief {
  int userId;
  String username;
  String nickname;
  bool hasAvatar;

  /// 头像版本（用户资料 updated_at），变化即需重新下载头像。
  String avatarUpdatedAt;
  bool isFriend;
  bool requestSent;

  ChatUserBrief({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.hasAvatar,
    required this.avatarUpdatedAt,
    required this.isFriend,
    required this.requestSent,
  });

  factory ChatUserBrief.fromJson(Map<String, dynamic> j) => ChatUserBrief(
    userId: (j['userId'] as num?)?.toInt() ?? 0,
    username: (j['username'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    hasAvatar: j['hasAvatar'] == true,
    avatarUpdatedAt: (j['avatarUpdatedAt'] ?? '') as String,
    isFriend: j['isFriend'] == true,
    requestSent: j['requestSent'] == true,
  );

  String get displayName => nickname.isEmpty ? username : nickname;
}

/// 好友 / 会话条目（会话接口返回相同结构，附带最后一条消息与未读数）。
class Friend {
  int userId;
  String username;
  String nickname;
  bool hasAvatar;

  /// 头像版本（用户资料 updated_at），变化即需重新下载头像。
  String avatarUpdatedAt;
  bool online;
  int unreadCount;
  String lastMessage;
  String lastMessageAt;

  /// 会话对端是否为好友；false 表示仅因消息往来（如邀请卡片）产生的非好友会话。
  bool isFriend;

  /// 我给该好友设置的备注（双向各自维护，可为空）。
  String remark;

  Friend({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.hasAvatar,
    required this.avatarUpdatedAt,
    required this.online,
    required this.unreadCount,
    required this.lastMessage,
    required this.lastMessageAt,
    this.isFriend = true,
    this.remark = '',
  });

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
    userId: (j['userId'] as num?)?.toInt() ?? 0,
    username: (j['username'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    hasAvatar: j['hasAvatar'] == true,
    avatarUpdatedAt: (j['avatarUpdatedAt'] ?? '') as String,
    online: j['online'] == true,
    unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    lastMessage: (j['lastMessage'] ?? '') as String,
    lastMessageAt: (j['lastMessageAt'] ?? '') as String,
    isFriend: (j['isFriend'] ?? true) == true,
    remark: (j['remark'] ?? '') as String,
  );

  /// 展示名：备注优先（微信式），其次昵称，最后用户名。
  String get displayName =>
      remark.isNotEmpty ? remark : (nickname.isEmpty ? username : nickname);

  /// 不带备注的原始昵称（好友详情页用于「昵称：xx / 备注：xx」双行展示）。
  String get originalName => nickname.isEmpty ? username : nickname;
}

/// 好友详情（/api/chat/friend/detail）：简短资料 + 备注 + 共同群聊。
class ChatFriendDetail {
  final ChatUserBrief friend;
  final String remark;
  final bool online;
  final List<ChatGroup> commonGroups;

  ChatFriendDetail({
    required this.friend,
    required this.remark,
    required this.online,
    required this.commonGroups,
  });

  factory ChatFriendDetail.fromJson(Map<String, dynamic> j) => ChatFriendDetail(
    friend: ChatUserBrief.fromJson(j['friend'] as Map<String, dynamic>? ?? {}),
    remark: (j['friend']?['remark'] ?? '') as String,
    online: j['friend']?['online'] == true,
    commonGroups: [
      for (final v in (j['commonGroups'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) ChatGroup.fromJson(v),
    ],
  );
}

/// 好友申请。
class FriendRequest {
  int id;
  int fromUserId;
  int toUserId;
  String fromUsername;
  String fromNickname;
  String toUsername;
  String toNickname;
  bool fromHasAvatar;
  String fromAvatarUpdatedAt;
  bool toHasAvatar;
  String toAvatarUpdatedAt;
  String message;
  int status; // 0=待处理 1=同意 2=拒绝
  String createdAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.fromUsername,
    required this.fromNickname,
    required this.toUsername,
    required this.toNickname,
    required this.fromHasAvatar,
    required this.fromAvatarUpdatedAt,
    required this.toHasAvatar,
    required this.toAvatarUpdatedAt,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
    id: (j['id'] as num?)?.toInt() ?? 0,
    fromUserId: (j['fromUserId'] as num?)?.toInt() ?? 0,
    toUserId: (j['toUserId'] as num?)?.toInt() ?? 0,
    fromUsername: (j['fromUsername'] ?? '') as String,
    fromNickname: (j['fromNickname'] ?? '') as String,
    toUsername: (j['toUsername'] ?? '') as String,
    toNickname: (j['toNickname'] ?? '') as String,
    fromHasAvatar: j['fromHasAvatar'] == true,
    fromAvatarUpdatedAt: (j['fromAvatarUpdatedAt'] ?? '') as String,
    toHasAvatar: j['toHasAvatar'] == true,
    toAvatarUpdatedAt: (j['toAvatarUpdatedAt'] ?? '') as String,
    message: (j['message'] ?? '') as String,
    status: (j['status'] as num?)?.toInt() ?? 0,
    createdAt: (j['createdAt'] ?? '') as String,
  );

  bool get isPending => status == 0;
}

/// 私聊消息。
///
/// [type] 区分消息形态：`text`=普通文本；`team_invite`=队伍邀请卡片（payload 携带
/// invitationId/teamName 等，见 API.md 6.7）；`system`=系统提示（如邀请处理结果）。
/// [groupId] 非 0 表示群聊消息（见 API.md 6.12），此时 receiverId 无意义。
class ChatMessage {
  int id;
  int senderId;
  int receiverId;
  int groupId;
  String content;
  String type;
  Map<String, dynamic> payload;
  String createdAt;
  bool read;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.groupId = 0,
    required this.content,
    this.type = 'text',
    Map<String, dynamic>? payload,
    required this.createdAt,
    required this.read,
  }) : payload = payload ?? const {};

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final t = ((j['type'] ?? '') as String?)?.trim() ?? '';
    return ChatMessage(
      id: (j['id'] as num?)?.toInt() ?? 0,
      senderId: (j['senderId'] as num?)?.toInt() ?? 0,
      receiverId: (j['receiverId'] as num?)?.toInt() ?? 0,
      groupId: (j['groupId'] as num?)?.toInt() ?? 0,
      content: (j['content'] ?? '') as String,
      type: t.isEmpty ? 'text' : t,
      payload: j['payload'] is Map<String, dynamic>
          ? j['payload'] as Map<String, dynamic>
          : const {},
      createdAt: (j['createdAt'] ?? '') as String,
      read: j['read'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'receiverId': receiverId,
    'groupId': groupId,
    'content': content,
    'type': type,
    'payload': payload,
    'createdAt': createdAt,
    'read': read,
  };
}

/// 群聊信息（/api/chat/group/info 的 group 对象）。
class ChatGroupInfo {
  int groupId;
  String name;
  int ownerId;
  String ownerUsername;
  String ownerNickname;
  String createdAt;
  int memberCount;
  List<ChatGroupMember> members;

  ChatGroupInfo({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.ownerUsername,
    required this.ownerNickname,
    required this.createdAt,
    required this.memberCount,
    required this.members,
  });

  factory ChatGroupInfo.fromJson(Map<String, dynamic> j) => ChatGroupInfo(
    groupId: (j['groupId'] as num?)?.toInt() ?? 0,
    name: (j['name'] ?? '') as String,
    ownerId: (j['ownerId'] as num?)?.toInt() ?? 0,
    ownerUsername: (j['ownerUsername'] ?? '') as String,
    ownerNickname: (j['ownerNickname'] ?? '') as String,
    createdAt: (j['createdAt'] ?? '') as String,
    memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
    members: [
      for (final v in (j['members'] as List<dynamic>? ?? []))
        if (v is Map<String, dynamic>) ChatGroupMember.fromJson(v),
    ],
  );

  String get ownerDisplayName => ownerNickname.isEmpty ? ownerUsername : ownerNickname;
}

/// 群成员条目。
class ChatGroupMember {
  int userId;
  String username;
  String nickname;
  bool hasAvatar;
  String avatarUpdatedAt;
  String joinedAt;
  bool isOwner;
  bool online;

  ChatGroupMember({
    required this.userId,
    required this.username,
    required this.nickname,
    required this.hasAvatar,
    required this.avatarUpdatedAt,
    required this.joinedAt,
    this.isOwner = false,
    this.online = false,
  });

  factory ChatGroupMember.fromJson(Map<String, dynamic> j) => ChatGroupMember(
    userId: (j['userId'] as num?)?.toInt() ?? 0,
    username: (j['username'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    hasAvatar: j['hasAvatar'] == true,
    avatarUpdatedAt: (j['avatarUpdatedAt'] ?? '') as String,
    joinedAt: (j['joinedAt'] ?? '') as String,
    isOwner: j['isOwner'] == true,
    online: j['online'] == true,
  );

  String get displayName => nickname.isEmpty ? username : nickname;
}

/// 群会话条目（/api/chat/conversations 的 groups 数组）。
class ChatGroup {
  int groupId;
  String name;
  int ownerId;
  String createdAt;
  int memberCount;
  int unreadCount;
  String lastMessage;
  String lastMessageAt;

  ChatGroup({
    required this.groupId,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.memberCount,
    required this.unreadCount,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  factory ChatGroup.fromJson(Map<String, dynamic> j) => ChatGroup(
    groupId: (j['groupId'] as num?)?.toInt() ?? 0,
    name: (j['name'] ?? '') as String,
    ownerId: (j['ownerId'] as num?)?.toInt() ?? 0,
    createdAt: (j['createdAt'] ?? '') as String,
    memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
    unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    lastMessage: (j['lastMessage'] ?? '') as String,
    lastMessageAt: (j['lastMessageAt'] ?? '') as String,
  );
}

/// 系统通知 / 业务通知。
class AppNotification {
  int id;
  String type;
  String title;
  String content;
  int refId;
  bool read;
  String createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.refId,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: (j['id'] as num?)?.toInt() ?? 0,
    type: (j['type'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    content: (j['content'] ?? '') as String,
    refId: (j['refId'] as num?)?.toInt() ?? 0,
    read: j['read'] == true,
    createdAt: (j['createdAt'] ?? '') as String,
  );
}

/// 三类未读计数（私聊 / 好友申请 / 通知）。
class UnreadSummary {
  int messages;
  int friendRequests;
  int notifications;

  UnreadSummary({this.messages = 0, this.friendRequests = 0, this.notifications = 0});

  int get total => messages + friendRequests + notifications;

  factory UnreadSummary.fromJson(Map<String, dynamic> j) => UnreadSummary(
    messages: (j['messages'] as num?)?.toInt() ?? 0,
    friendRequests: (j['friendRequests'] as num?)?.toInt() ?? 0,
    notifications: (j['notifications'] as num?)?.toInt() ?? 0,
  );
}

/// 媒体上传结果（/api/chat/media/upload 的响应）。
///
/// 服务端只回登记信息，不回可访问 URL：媒体接口是 POST + 信封鉴权，
/// 客户端拿到 key 后需经 [ChatSDK.fetchChatMedia] 换取字节。
class MediaUploadResult {
  final String key;
  final String kind; // image / video
  final int size;
  final String mime;

  MediaUploadResult({
    required this.key,
    required this.kind,
    required this.size,
    required this.mime,
  });

  bool get isVideo => kind == 'video';
}

/// 聊天媒体在本地缓存中的文件名：去掉 `chat/` 目录部分并加前缀，
/// 避免与头像等其他缓存文件重名。
String mediaCacheName(String mediaKey) {
  final name = mediaKey.split('/').last;
  return 'media_$name';
}

/// 好友头像在本地缓存中的文件名。
///
/// **必须带上服务端标记**：`userId` 只在单个服务端内唯一，两台服务器上的
/// `userId=7` 是两个不同的人。只按 id 命名的话，切换服务器后一旦版本戳
/// 恰好相同，就会命中另一台服务器上那个人的缓存头像。
String avatarCacheName(int userId) => 'avatar_${ServerSettings.cacheTag}_$userId';

/// 头像版本在 SharedPreferences 里的键，同样按服务端隔离（与
/// [avatarCacheName] 必须成对，否则文件换了、版本还在，缓存判断会错乱）。
String avatarVersionKey(int userId) => 'avatar_ver_${ServerSettings.cacheTag}_$userId';

/// 聊天媒体的 MediaType，按文件名扩展名推断。
///
/// `package:http` 不会从路径推断类型，[buildMediaPart] 组装分片时若不显式
/// 传 contentType 会回退成 `application/octet-stream`，从而被服务端的 MIME
/// 白名单拒绝（与头像上传同一个坑，见 base.dart 的 avatarMediaType）。
MediaType chatMediaType(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' => MediaType('image', 'png'),
    'gif' => MediaType('image', 'gif'),
    'webp' => MediaType('image', 'webp'),
    'bmp' => MediaType('image', 'bmp'),
    'mp4' => MediaType('video', 'mp4'),
    'm4v' => MediaType('video', 'x-m4v'),
    'mov' => MediaType('video', 'quicktime'),
    'webm' => MediaType('video', 'webm'),
    'mkv' => MediaType('video', 'x-matroska'),
    '3gp' => MediaType('video', '3gpp'),
    _ => MediaType('image', 'jpeg'),
  };
}

// ==================== HTTP SDK ====================

class ChatSDK {
  static const Duration _requestTimeout = Duration(seconds: 10);

  /// 媒体上传超时：视频动辄数十 MB，通用的 10 秒超时必然失败。
  static const Duration _uploadTimeout = Duration(minutes: 5);

  /// 媒体下载超时：需要完整拉取一个视频文件。
  static const Duration _mediaTimeout = Duration(seconds: 60);

  static Uri _uri(String path) => Uri.parse("${ServerSettings.baseUrl}$path");

  static Future<DCResponse> _post(String path, UserObj user, Map<String, dynamic> data) async {
    final res = await http.post(
      _uri(path),
      headers: {"Content-Type": "application/json"},
      body: DCRequest.fromJson(user, data).toString(),
    ).timeout(_requestTimeout);
    return DCResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      requestToken: user.token,
    );
  }

  static DCResponse _authed(DCResponse r) {
    if (r.code == 404 && r.data.isEmpty) throw AuthExpiredException(r.requestToken);
    if (r.code != 200) {
      throw ApiException((r.data['error'] ?? '操作失败（${r.code}）').toString());
    }
    return r;
  }

  static List<Map<String, dynamic>> _list(dynamic raw) => [
    for (final v in (raw as List<dynamic>? ?? []))
      if (v is Map<String, dynamic>) v,
  ];

  /// 按用户名/昵称搜索用户。
  static Future<List<ChatUserBrief>> searchUsers(UserObj user, String keyword) async {
    final r = _authed(await _post('/api/chat/friend/search', user, {'keyword': keyword}));
    return [for (final j in _list(r.data['users'])) ChatUserBrief.fromJson(j)];
  }

  /// 发送好友申请。
  static Future<void> sendFriendRequest(UserObj user, int targetUserId, String message) async {
    _authed(await _post('/api/chat/friend/request', user, {
      'targetUserId': targetUserId,
      'message': message,
    }));
  }

  /// 好友申请列表。box: inbox=收到的 / outbox=发出的。
  static Future<List<FriendRequest>> fetchFriendRequests(UserObj user, {String box = 'inbox'}) async {
    final r = _authed(await _post('/api/chat/friend/request/list', user, {'box': box}));
    return [for (final j in _list(r.data['requests'])) FriendRequest.fromJson(j)];
  }

  /// 同意 / 拒绝好友申请。
  static Future<void> respondFriendRequest(UserObj user, int requestId, bool accept) async {
    _authed(await _post('/api/chat/friend/respond', user, {
      'requestId': requestId,
      'accept': accept,
    }));
  }

  /// 好友列表（含在线状态、未读数、最后一条消息）。
  static Future<List<Friend>> fetchFriends(UserObj user) async {
    final r = _authed(await _post('/api/chat/friend/list', user, {}));
    return [for (final j in _list(r.data['friends'])) Friend.fromJson(j)];
  }

  /// 删除好友。
  static Future<void> deleteFriend(UserObj user, int friendId) async {
    _authed(await _post('/api/chat/friend/delete', user, {'friendId': friendId}));
  }

  /// 好友详情：对方简短资料 + 我设置的备注 + 双方共同群聊（一次请求全部返回）。
  static Future<ChatFriendDetail> fetchFriendDetail(UserObj user, int friendId) async {
    final r = _authed(await _post('/api/chat/friend/detail', user, {'friendId': friendId}));
    return ChatFriendDetail.fromJson(r.data);
  }

  /// 设置/清空我给某好友的备注（空串表示清空）。
  static Future<String> setFriendRemark(UserObj user, int friendId, String remark) async {
    final r = _authed(await _post('/api/chat/friend/remark', user, {
      'friendId': friendId,
      'remark': remark,
    }));
    return (r.data['remark'] ?? '') as String;
  }

  /// 发送私聊消息，返回服务器落库后的完整消息。
  static Future<ChatMessage> sendMessage(UserObj user, int receiverId, String content) async {
    final r = _authed(await _post('/api/chat/message/send', user, {
      'receiverId': receiverId,
      'content': content,
    }));
    return ChatMessage.fromJson(r.data['message'] as Map<String, dynamic>);
  }

  /// 拉取与某好友的历史消息（按 id 倒序，beforeId 游标分页）。
  static Future<List<ChatMessage>> fetchHistory(
    UserObj user,
    int friendId, {
    int beforeId = 0,
    int limit = 50,
  }) async {
    final r = _authed(await _post('/api/chat/message/history', user, {
      'friendId': friendId,
      'beforeId': beforeId,
      'limit': limit,
    }));
    return [for (final j in _list(r.data['messages'])) ChatMessage.fromJson(j)];
  }

  /// 上报已读。
  static Future<void> markRead(UserObj user, int friendId) async {
    _authed(await _post('/api/chat/message/read', user, {'friendId': friendId}));
  }

  /// 会话列表：返回 (好友/非好友会话, 加入的群聊) 两个数组。
  static Future<(List<Friend>, List<ChatGroup>)> fetchConversations(UserObj user) async {
    final r = _authed(await _post('/api/chat/conversations', user, {}));
    return (
      [for (final j in _list(r.data['conversations'])) Friend.fromJson(j)],
      [for (final j in _list(r.data['groups'])) ChatGroup.fromJson(j)],
    );
  }

  // ==================== 群聊 ====================

  /// 创建群聊（创建者成为群主），返回新群 ID。
  static Future<int> createGroup(UserObj user, String name, List<int> memberIds) async {
    final r = _authed(await _post('/api/chat/group/create', user, {
      'name': name,
      'memberIds': memberIds,
    }));
    return (r.data['groupId'] as num?)?.toInt() ?? 0;
  }

  /// 群信息（群名/群主/创建时间/成员列表，见 API.md 6.12.2）。
  static Future<ChatGroupInfo> fetchGroupInfo(UserObj user, int groupId) async {
    final r = _authed(await _post('/api/chat/group/info', user, {'groupId': groupId}));
    return ChatGroupInfo.fromJson(r.data['group'] as Map<String, dynamic>);
  }

  /// 拉人入群（仅群主）。
  static Future<void> groupInvite(UserObj user, int groupId, List<int> memberIds) async {
    _authed(await _post('/api/chat/group/invite', user, {
      'groupId': groupId,
      'memberIds': memberIds,
    }));
  }

  /// 移出成员（仅群主）。
  static Future<void> groupKick(UserObj user, int groupId, int targetUserId) async {
    _authed(await _post('/api/chat/group/kick', user, {
      'groupId': groupId,
      'targetUserId': targetUserId,
    }));
  }

  /// 退出群聊（群主不可退）。
  static Future<void> leaveGroup(UserObj user, int groupId) async {
    _authed(await _post('/api/chat/group/leave', user, {'groupId': groupId}));
  }

  /// 解散群聊（仅群主）。
  static Future<void> disbandGroup(UserObj user, int groupId) async {
    _authed(await _post('/api/chat/group/disband', user, {'groupId': groupId}));
  }

  /// 发送群消息，返回服务器落库后的完整消息。
  static Future<ChatMessage> sendGroupMessage(UserObj user, int groupId, String content) async {
    final r = _authed(await _post('/api/chat/group/message/send', user, {
      'groupId': groupId,
      'content': content,
    }));
    return ChatMessage.fromJson(r.data['message'] as Map<String, dynamic>);
  }

  /// 拉取群历史消息（按 id 倒序，beforeId 游标分页）。
  static Future<List<ChatMessage>> fetchGroupHistory(
    UserObj user,
    int groupId, {
    int beforeId = 0,
    int limit = 50,
  }) async {
    final r = _authed(await _post('/api/chat/group/message/history', user, {
      'groupId': groupId,
      'beforeId': beforeId,
      'limit': limit,
    }));
    return [for (final j in _list(r.data['messages'])) ChatMessage.fromJson(j)];
  }

  /// 上报群聊已读。
  static Future<void> markGroupRead(UserObj user, int groupId) async {
    _authed(await _post('/api/chat/group/message/read', user, {'groupId': groupId}));
  }

  /// 通知列表。
  static Future<List<AppNotification>> fetchNotifications(
    UserObj user, {
    int beforeId = 0,
    int limit = 50,
  }) async {
    final r = _authed(await _post('/api/chat/notify/list', user, {
      'beforeId': beforeId,
      'limit': limit,
    }));
    return [for (final j in _list(r.data['notifications'])) AppNotification.fromJson(j)];
  }

  /// 通知已读。id 为空时全部已读。
  static Future<void> markNotificationRead(UserObj user, {int? id}) async {
    _authed(await _post('/api/chat/notify/read', user, {'id': ?id}));
  }

  /// 三类未读计数。
  static Future<UnreadSummary> fetchUnreadCount(UserObj user) async {
    final r = _authed(await _post('/api/chat/notify/unread-count', user, {}));
    return UnreadSummary.fromJson(r.data);
  }

  /// 下载指定用户的头像到本地缓存；无头像返回 null。
  /// [version] 为服务端下发的头像版本（user_profiles.updated_at）：与本地记录
  /// 一致时直接用缓存秒开；不一致或未知时重新下载并覆盖——
  /// 保证好友系统头像始终与用户系统的 avatar 同步。
  static Future<CachedMedia?> fetchUserAvatar(
    UserObj user,
    int userId, {
    String? version,
  }) async {
    if (user.isAnonymous) return null;
    final name = avatarCacheName(userId);
    final verKey = avatarVersionKey(userId);
    final cachedVersion = Cache.p?.getString(verKey);
    if (version != null && cachedVersion == version) {
      final hit = await loadCachedMedia(name);
      if (hit != null) return hit;
    }
    final res = await http.post(
      _uri('/api/chat/avatar'),
      headers: {"Content-Type": "application/json"},
      body: DCRequest.fromJson(user, {'userId': userId}).toString(),
    ).timeout(_requestTimeout);
    final contentType = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || res.bodyBytes.isEmpty || contentType.contains('json')) {
      return null;
    }
    // 覆盖写入（路径不变但内容已更新）：旧图的解码缓存由 writeCachedMedia
    // 在覆盖前清掉。
    final media = await writeCachedMedia(name, res.bodyBytes);
    if (version != null) {
      await Cache.p?.setString(verKey, version);
    }
    return media;
  }

  // ==================== 媒体消息（图片 / 视频） ====================

  /// 上传媒体文件，返回服务端登记的 key。
  ///
  /// 走独立的长超时：视频动辄数十 MB，共用的 10 秒 [_requestTimeout] 不够用。
  static Future<MediaUploadResult> uploadChatMedia(UserObj user, XFile file) async {
    final req = http.MultipartRequest('POST', _uri('/api/chat/media/upload'));
    req.fields['body'] = DCRequest.fromJson(user, {}).toString();
    req.files.add(
      await buildMediaPart('file', file, chatMediaType(file.name)),
    );
    final res = await http.Response.fromStream(
      await req.send().timeout(_uploadTimeout),
    ).timeout(_uploadTimeout);
    if (res.statusCode != 200) {
      throw ApiException('上传失败（HTTP ${res.statusCode}）');
    }
    final dcRes = DCResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
      requestToken: user.token,
    );
    if (dcRes.code == 404) throw AuthExpiredException(user.token);
    if (dcRes.code != 200) {
      // 服务端把拒绝原因放在 data.error（格式不支持、超出大小等）。
      final reason = ((dcRes.data['error'] ?? '') as String).trim();
      throw ApiException(reason.isNotEmpty ? reason : '上传失败（${dcRes.code}）');
    }
    return MediaUploadResult(
      key: (dcRes.data['key'] ?? '') as String,
      kind: (dcRes.data['kind'] ?? 'image') as String,
      size: (dcRes.data['size'] as num?)?.toInt() ?? 0,
      mime: (dcRes.data['mime'] ?? '') as String,
    );
  }

  /// 下载聊天媒体到本地缓存；文件不存在或无权访问时返回 null。
  ///
  /// 与头像同理：接口是 POST + 信封鉴权，`Image.network` 与播放器都带不了
  /// 信封，所以必须先落到本地缓存再交给渲染层。缓存名由 mediaKey 推导且内容
  /// 不可变（key 含随机 UUID），因此本地存在即视为有效，无需版本校验。
  static Future<CachedMedia?> fetchChatMedia(UserObj user, String mediaKey) async {
    if (user.isAnonymous || mediaKey.isEmpty) return null;
    final name = mediaCacheName(mediaKey);
    final hit = await loadCachedMedia(name);
    if (hit != null) return hit;
    final res = await http.post(
      _uri('/api/chat/media'),
      headers: {'Content-Type': 'application/json'},
      body: DCRequest.fromJson(user, {'key': mediaKey}).toString(),
    ).timeout(_mediaTimeout);
    // 接口正常时返回原始字节流；出错时返回 JSON 信封（403 无权 / 404 不存在）。
    final contentType = res.headers['content-type'] ?? '';
    if (res.statusCode != 200 || res.bodyBytes.isEmpty || contentType.contains('json')) {
      return null;
    }
    return writeCachedMedia(name, res.bodyBytes);
  }

  /// 发送图片 / 视频消息（私聊）。
  ///
  /// [width] / [height] / [durationMs] 仅用于渲染占位与播放器尺寸，
  /// 服务端原样透传，不参与校验。
  static Future<ChatMessage> sendMediaMessage(
    UserObj user,
    int receiverId,
    String mediaKey, {
    int width = 0,
    int height = 0,
    int durationMs = 0,
    String fileName = '',
  }) async {
    final r = _authed(await _post('/api/chat/message/send-media', user, {
      'receiverId': receiverId,
      'mediaKey': mediaKey,
      'width': width,
      'height': height,
      'durationMs': durationMs,
      'fileName': fileName,
    }));
    return ChatMessage.fromJson(r.data['message'] as Map<String, dynamic>);
  }

  /// 发送图片 / 视频消息（群聊）。
  static Future<ChatMessage> sendGroupMediaMessage(
    UserObj user,
    int groupId,
    String mediaKey, {
    int width = 0,
    int height = 0,
    int durationMs = 0,
    String fileName = '',
  }) async {
    final r = _authed(await _post('/api/chat/group/message/send-media', user, {
      'groupId': groupId,
      'mediaKey': mediaKey,
      'width': width,
      'height': height,
      'durationMs': durationMs,
      'fileName': fileName,
    }));
    return ChatMessage.fromJson(r.data['message'] as Map<String, dynamic>);
  }
}

// ==================== WebSocket 长连接 ====================

enum ChatConnStatus { connected, connecting, disconnected }

/// 服务端推送事件。type 与后端 ChatWsHandler 约定一致。
class ChatEvent {
  final String type;
  final Map<String, dynamic> data;

  ChatEvent(this.type, this.data);
}

/// 全局 WebSocket 连接管理：登录即连、断线自动重连、心跳保活、
/// 把推送转成广播事件流，并维护三类未读计数。
class ChatSocket extends GetxService {
  final auth = Get.find<AuthService>();

  final status = ChatConnStatus.disconnected.obs;
  final unread = UnreadSummary().obs;

  final _events = StreamController<ChatEvent>.broadcast();
  Stream<ChatEvent> get events => _events.stream;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _retrySeconds = 1;
  bool _wantConnected = false;
  Worker? _authWorker;

  @override
  void onInit() {
    super.onInit();
    // 跟随登录态：登录连接，登出断开。
    _authWorker = ever(auth.userObj, (_) => _sync());
    _sync();
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _events.close();
    super.onClose();
  }

  void _sync() {
    if (auth.isLoggedIn) {
      _connect();
    } else {
      _teardown();
    }
  }

  /// 服务端地址变更后重建长连接。
  ///
  /// 必须清掉旧的退避计数与待触发的重连定时器，否则那条定时器仍会拿着
  /// **旧地址**把连接重新拉起来，表现为「改了地址却还在连老的」。
  /// 已登出时 [_sync] 直接拆除，无副作用。
  void reconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _retrySeconds = 1;
    _teardownSocketOnly();
    status.value = ChatConnStatus.disconnected;
    unread.value = UnreadSummary();
    _sync();
  }

  Future<void> _connect() async {
    if (status.value == ChatConnStatus.connected ||
        status.value == ChatConnStatus.connecting) {
      return;
    }
    final token = auth.userObj.value.token;
    if (token == null || token.isEmpty) return;

    status.value = ChatConnStatus.connecting;
    _wantConnected = true;
    try {
      // WebSocketChannel 只接受 ws/wss scheme，由 HTTP scheme 推导。
      final uri = Uri.parse(
        '${ServerSettings.baseUrl}/ws/chat?token=${Uri.encodeQueryComponent(token)}',
      ).replace(scheme: ServerSettings.wsScheme);
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      _onConnected();
      channel.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _teardownSocketOnly();
      _scheduleReconnect();
    }
  }

  void _onConnected() {
    status.value = ChatConnStatus.connected;
    _retrySeconds = 1;
    _pingTimer?.cancel();
    // 心跳：定期 ping 防止连接空闲被切断。
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
    // 连接后立即校准一次未读数，兜底离线期间丢失的推送。
    refreshUnread();
  }

  void _onData(dynamic raw) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = (json['type'] ?? '') as String;
    final data = (json['data'] ?? {}) as Map<String, dynamic>;
    switch (type) {
      case 'summary':
        // 服务端推送 data: { summary: {...}, onlineFriends: [...] }
        unread.value = UnreadSummary.fromJson(
          (data['summary'] ?? const {}) as Map<String, dynamic>,
        );
        return;
      case 'message.new':
        unread.value.messages += 1;
        unread.refresh();
        break;
      case 'group.message.new':
        // 群消息未读并入 messages 计数；事件本身照常广播给页面。
        unread.value.messages += 1;
        unread.refresh();
        break;
      case 'friend.request':
        unread.value.friendRequests += 1;
        unread.refresh();
        break;
      case 'friend.accepted':
      case 'notify.new':
        unread.value.notifications += 1;
        unread.refresh();
        break;
      case 'notify.removed':
        // 管理员撤回系统公告：该条可能已计入未读，直接回读服务端真值校准，
        // 事件本身照常广播，通知页收到后重新拉取列表。
        refreshUnread();
        break;
      case 'pong':
        return;
    }
    _events.add(ChatEvent(type, data));
  }

  /// 供页面在本地已读后同步扣减红点。
  void clearUnreadMessages(int n) {
    unread.value.messages = n > unread.value.messages ? 0 : unread.value.messages - n;
    unread.refresh();
  }

  void clearUnreadFriendRequests(int n) {
    unread.value.friendRequests = n > unread.value.friendRequests ? 0 : unread.value.friendRequests - n;
    unread.refresh();
  }

  /// 从服务端重新拉取三类未读数并整体覆盖本地徽标。
  /// 供页面在已读等操作后精确校准，避免本地加减法与真值漂移。
  Future<void> refreshUnread() async {
    try {
      final s = await ChatSDK.fetchUnreadCount(auth.userObj.value);
      unread.value = s;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      // 网络波动时静默，下次事件/重连再校准。
    }
  }

  void _scheduleReconnect() {
    _teardownSocketOnly();
    if (!_wantConnected || !auth.isLoggedIn) {
      status.value = ChatConnStatus.disconnected;
      return;
    }
    status.value = ChatConnStatus.disconnected;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _retrySeconds), () {
      _retrySeconds = (_retrySeconds * 2).clamp(1, 60);
      _connect();
    });
  }

  void _teardownSocketOnly() {
    _pingTimer?.cancel();
    _pingTimer = null;
    final c = _channel;
    _channel = null;
    try {
      c?.sink.close();
    } catch (_) {}
  }

  void _teardown() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _teardownSocketOnly();
    status.value = ChatConnStatus.disconnected;
    unread.value = UnreadSummary();
  }
}
