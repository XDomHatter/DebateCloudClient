import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 取上传文件名：优先选择器给出的 name（Web 上是用户选中的真实文件名），
/// 异常时退回从路径提取，兼容 Windows 与 POSIX 分隔符。
String _mediaFileName(XFile file) {
  final name = file.name;
  if (name.isNotEmpty && !name.contains('/') && !name.contains('\\')) {
    return name;
  }
  final path = file.path;
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// 会话列表页（消息 tab 首页）。
class ChatHomeController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final conversations = <Friend>[].obs;
  final groups = <ChatGroup>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  StreamSubscription? _sub;
  Worker? _authWorker;

  /// socket 事件触发的刷新节流窗口：每条群消息都全量拉取会话既浪费
  /// 带宽，也让常驻的消息 tab 反复重建；窗口内首次立即刷新，其余事件
  /// 合并到窗口尾部一次性补发。下拉刷新、进入页面等主动调用不受限。
  static const Duration _socketReloadInterval = Duration(seconds: 3);
  DateTime _lastLoadAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingReload;

  @override
  void onInit() {
    super.onInit();
    load();
    // 实时新消息（私聊/群聊）与群成员变动到达时刷新会话列表。
    _sub = socket.events.listen((e) {
      if (e.type == 'message.new' ||
          e.type == 'group.message.new' ||
          e.type == 'group.updated') {
        _throttledLoad();
      }
    });
    // 消息 tab 常驻 IndexedStack，控制器不会重建：
    // 登录/登出后必须重拉会话，否则停留在旧状态。
    _authWorker = ever(auth.userObj, (_) => load());
  }

  @override
  void onClose() {
    _sub?.cancel();
    _authWorker?.dispose();
    _pendingReload?.cancel();
    super.onClose();
  }

  /// 距上次 load 不足一个窗口时挂一个尾部 Timer 合并后续事件；
  /// 已有待发 Timer 时直接并入，不再顺延。
  void _throttledLoad() {
    final elapsed = DateTime.now().difference(_lastLoadAt);
    if (elapsed >= _socketReloadInterval) {
      load();
      return;
    }
    _pendingReload ??= Timer(_socketReloadInterval - elapsed, () {
      _pendingReload = null;
      load();
    });
  }

  Future<void> load() async {
    _lastLoadAt = DateTime.now();
    // 未登录不发需要鉴权的请求：本控制器随 IndexedStack 常驻，应用启动
    // （token 为空）和登出后都会被触发，此时请求只会得到 404。
    if (!auth.isLoggedIn) {
      conversations.clear();
      groups.clear();
      isLoading.value = false;
      errorMessage.value = '';
      return;
    }
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final (convs, gs) = await ChatSDK.fetchConversations(auth.userObj.value);
      conversations.value = convs;
      groups.value = gs;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  /// 好友会话与群会话按最后一条消息时间归并（无消息的排末尾），
  /// 元素用 `is Friend` / `is ChatGroup` 区分，供视图分发渲染。
  static List<Object> mergeEntries(List<Friend> friends, List<ChatGroup> groups) {
    final entries = <Object>[...friends, ...groups];
    String key(Object e) => e is Friend ? e.lastMessageAt : (e as ChatGroup).lastMessageAt;
    entries.sort((a, b) {
      final ta = key(a);
      final tb = key(b);
      if (ta.isEmpty && tb.isNotEmpty) return 1;
      if (ta.isNotEmpty && tb.isEmpty) return -1;
      return tb.compareTo(ta);
    });
    return entries;
  }
}

/// 好友列表 + 搜索添加好友。
class ContactsController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final friends = <Friend>[].obs;
  final searchResults = <ChatUserBrief>[].obs;
  final isSearching = false.obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    load();
    // 好友上线/下线实时刷新在线状态。
    _sub = socket.events.listen((e) {
      if (e.type == 'presence') load();
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      friends.value = await ChatSDK.fetchFriends(auth.userObj.value);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  String _lastKeyword = '';

  Future<void> search(String keyword) async {
    _lastKeyword = keyword;
    if (keyword.trim().isEmpty) {
      searchResults.value = [];
      return;
    }
    isSearching.value = true;
    try {
      searchResults.value = await ChatSDK.searchUsers(auth.userObj.value, keyword.trim());
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      searchResults.value = [];
      AppSnackbar.error('搜索失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isSearching.value = false;
    }
  }

  Future<bool> sendRequest(int targetUserId) async {
    try {
      await ChatSDK.sendFriendRequest(auth.userObj.value, targetUserId, '');
      // 重发一次搜索以刷新该用户按钮状态。
      await search(_lastKeyword);
      return true;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    }
    return false;
  }
}

/// 好友申请处理页。
class FriendRequestsController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final inbox = <FriendRequest>[].obs;
  final outbox = <FriendRequest>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    load();
    _sub = socket.events.listen((e) {
      if (e.type == 'friend.request' || e.type == 'friend.accepted') load();
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final results = await Future.wait([
        ChatSDK.fetchFriendRequests(auth.userObj.value, box: 'inbox'),
        ChatSDK.fetchFriendRequests(auth.userObj.value, box: 'outbox'),
      ]);
      inbox.value = results[0];
      outbox.value = results[1];
      // 已全部处理后同步扣减红点。
      final pending = inbox.where((r) => r.isPending).length;
      if (socket.unread.value.friendRequests > pending) {
        socket.clearUnreadFriendRequests(socket.unread.value.friendRequests - pending);
      }
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> respond(FriendRequest r, bool accept) async {
    try {
      await ChatSDK.respondFriendRequest(auth.userObj.value, r.id, accept);
      await load();
      // 服务端已把该申请对应的通知标为已读，回读未读数让"通知"红点立即同步。
      await socket.refreshUnread();
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    }
  }
}

/// 一对一聊天窗口。
class ChatDetailController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final Friend friend;
  final messages = <ChatMessage>[].obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final errorMessage = ''.obs;

  /// 邀请卡片状态：invitationId → status（0=待处理 1=已接受 2=已拒绝）。
  /// 接收方从"我的邀请"接口回读权威状态；双方都可从系统消息 payload 回填。
  final inviteStatuses = <int, int>{}.obs;

  /// 好友在线状态，随服务端 presence 推送实时更新。
  final online = false.obs;

  /// 我给该好友的备注（好友详情页保存后回写，标题即时刷新）。
  final remark = ''.obs;

  /// 媒体上传中：期间禁用附件按钮，避免并发上传把带宽吃满。
  final isUploading = false.obs;

  /// 已读回执版本号：markRead 就地改写消息对象的 read 字段（列表身份
  /// 不变），以此 tick 通知已读对勾重绘——不再对整表 refresh。
  final readReceiptTick = 0.obs;

  bool _hasMore = true;
  StreamSubscription? _sub;

  ChatDetailController(this.friend) {
    online.value = friend.online;
    remark.value = friend.remark;
  }

  /// 消息按 id 倒序存储（列表头部是最新的），UI 用 reverse ListView 直接展示。
  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    load();
    markRead();
    _sub = socket.events.listen((e) {
      if (e.type == 'message.new') {
        final m = ChatMessage.fromJson(e.data['message'] ?? {});
        final other = m.senderId == friend.userId || m.receiverId == friend.userId;
        if (!other) return;
        messages.insert(0, m);
        _applyInviteSystemMessages([m]);
        markRead();
      } else if (e.type == 'presence') {
        final userId = (e.data['userId'] as num?)?.toInt() ?? 0;
        if (userId == friend.userId) {
          final v = e.data['online'] == true;
          online.value = v;
          friend.online = v;
        }
      }
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final list = await ChatSDK.fetchHistory(auth.userObj.value, friend.userId);
      messages.value = list;
      _hasMore = list.length >= 50;
      _applyInviteSystemMessages(list);
      await _syncInviteStatusesFromServer();
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || isLoadingMore.value || messages.isEmpty) return;
    isLoadingMore.value = true;
    try {
      final older = await ChatSDK.fetchHistory(
        auth.userObj.value,
        friend.userId,
        beforeId: messages.last.id,
      );
      messages.addAll(older);
      _hasMore = older.length >= 50;
      _applyInviteSystemMessages(older);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      AppSnackbar.error('加载失败', '请检查服务器连接');
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> send(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    if (!friend.isFriend) {
      AppSnackbar.show('提示', '添加好友后才能发送消息');
      return;
    }
    try {
      final m = await ChatSDK.sendMessage(auth.userObj.value, friend.userId, text);
      // 去重：socket 推送的同一消息不再插入。
      messages.removeWhere((x) => x.id == m.id);
      messages.insert(0, m);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    }
  }

  /// 上传并发送媒体消息（图片 / 视频）。
  ///
  /// 两阶段：先上传拿 key（独立长超时，可单独重试），再按普通消息发送——
  /// 后者复用好友校验与推送链路，失败时不会在会话里留下半个消息。
  /// [width] / [height] 仅用于接收端按比例占位，服务端原样透传。
  Future<void> sendMedia(
    XFile file, {
    required bool isVideo,
    int width = 0,
    int height = 0,
    int durationMs = 0,
  }) async {
    if (!friend.isFriend) {
      AppSnackbar.show('提示', '添加好友后才能发送消息');
      return;
    }
    if (isUploading.value) return;
    isUploading.value = true;
    try {
      final uploaded = await ChatSDK.uploadChatMedia(auth.userObj.value, file);
      final m = await ChatSDK.sendMediaMessage(
        auth.userObj.value,
        friend.userId,
        uploaded.key,
        width: width,
        height: height,
        durationMs: durationMs,
        fileName: _mediaFileName(file),
      );
      // 去重：socket 推送的同一消息不再插入。
      messages.removeWhere((x) => x.id == m.id);
      messages.insert(0, m);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isUploading.value = false;
    }
  }

  /// 在邀请卡片上直接接受/拒绝（复用赛事模块的响应邀请接口）。
  Future<void> respondInvite(ChatMessage m, bool accept) async {
    final invitationId = (m.payload['invitationId'] as num?)?.toInt() ?? 0;
    if (invitationId <= 0) return;
    try {
      await SDK.respondInvitation(
        auth.userObj.value,
        invitationId: invitationId,
        accept: accept,
      );
      inviteStatuses[invitationId] = accept ? 1 : 2;
      inviteStatuses.refresh();
      AppSnackbar.show(accept ? '已接受' : '已拒绝', accept ? '欢迎加入队伍' : '已拒绝该入队邀请');
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
      // 可能已在"我的赛事"等其他入口处理过，回读最新状态。
      await _syncInviteStatusesFromServer();
    }
  }

  /// 从消息流中的系统消息回填邀请状态（接受/拒绝结果对双方都可见）。
  void _applyInviteSystemMessages(Iterable<ChatMessage> msgs) {
    var changed = false;
    for (final m in msgs) {
      if (m.type != 'system') continue;
      final invitationId = (m.payload['invitationId'] as num?)?.toInt() ?? 0;
      final result = m.payload['result'];
      final status = result == 'accepted' ? 1 : (result == 'rejected' ? 2 : null);
      if (invitationId > 0 && status != null && inviteStatuses[invitationId] != status) {
        inviteStatuses[invitationId] = status;
        changed = true;
      }
    }
    if (changed) inviteStatuses.refresh();
  }

  /// 我是接收方时，从"我的邀请"接口回读权威状态，
  /// 覆盖在"我的赛事"页等其他入口处理过的情况。
  Future<void> _syncInviteStatusesFromServer() async {
    final hasIncomingCard = messages.any(
      (m) => m.type == 'team_invite' && m.senderId == friend.userId,
    );
    if (!hasIncomingCard) return;
    try {
      final invitations = await SDK.fetchMyInvitations(auth.userObj.value);
      var changed = false;
      for (final inv in invitations) {
        if (inviteStatuses[inv.id] != inv.status) {
          inviteStatuses[inv.id] = inv.status;
          changed = true;
        }
      }
      if (changed) inviteStatuses.refresh();
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      // 状态同步失败不影响消息展示，卡片按当前已知状态渲染。
    }
  }

  Future<void> markRead() async {
    try {
      await ChatSDK.markRead(auth.userObj.value, friend.userId);
      final cleared = friend.unreadCount;
      friend.unreadCount = 0;
      if (cleared > 0) socket.clearUnreadMessages(cleared);
      // 本地标记已读：只改字段 + bump tick，让已读对勾自己重绘；
      // 整表 refresh 会让所有可见气泡（含 markdown 重排版）白重建一遍。
      for (final m in messages) {
        if (m.senderId == friend.userId) m.read = true;
      }
      readReceiptTick.value++;
    } catch (_) {}
  }
}

/// 系统通知列表。
class NotificationsController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final notifications = <AppNotification>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    load();
    _sub = socket.events.listen((e) {
      if (e.type == 'notify.new' ||
          e.type == 'friend.accepted' ||
          e.type == 'notify.removed') {
        load();
      }
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      notifications.value = await ChatSDK.fetchNotifications(auth.userObj.value);
      // 打开/刷新通知页即视为已读：自动标记并校准红点。
      if (notifications.any((n) => !n.read)) {
        try {
          await _markAllRead();
        } on AuthExpiredException {
          rethrow;
        } catch (_) {
          // 自动已读失败不影响页面展示，可手动点"全部已读"。
        }
      }
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> markAllRead() async {
    try {
      await _markAllRead();
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    }
  }

  /// 服务端全部已读 + 本地列表置已读 + 回读未读数精确校准红点。
  /// 不用本地列表未读数做减法扣徽标：列表只含第一页且可能与徽标漂移，
  /// 减法会残留未读数导致红点不灭，回读服务端真值才能保证归零。
  Future<void> _markAllRead() async {
    await ChatSDK.markNotificationRead(auth.userObj.value);
    for (final n in notifications) {
      n.read = true;
    }
    notifications.refresh();
    await socket.refreshUnread();
  }
}

/// 创建群聊：填写群名 + 从好友中勾选初始成员。
class GroupCreateController extends GetxController {
  final auth = Get.find<AuthService>();

  final friends = <Friend>[].obs;
  final selected = <int>[].obs;
  final isLoading = false.obs;
  final isCreating = false.obs;
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
      friends.value = await ChatSDK.fetchFriends(auth.userObj.value);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  void toggle(int userId) {
    if (selected.contains(userId)) {
      selected.remove(userId);
    } else {
      selected.add(userId);
    }
  }

  /// 创建成功返回新群 ID（失败弹提示返回 0，由视图决定是否跳转）。
  Future<int> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      AppSnackbar.show('提示', '请填写群名');
      return 0;
    }
    isCreating.value = true;
    try {
      final groupId = await ChatSDK.createGroup(
        auth.userObj.value, trimmed, selected.toList());
      AppSnackbar.success('创建成功', '群聊「$trimmed」已创建');
      return groupId;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('创建失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isCreating.value = false;
    }
    return 0;
  }
}

/// 群聊窗口。
class GroupChatController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final ChatGroup group;
  final messages = <ChatMessage>[].obs;
  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final errorMessage = ''.obs;
  final memberCount = 0.obs;

  /// 成员资料映射（userId → 成员），供气泡渲染发送者昵称/头像。
  final members = <int, ChatGroupMember>{}.obs;

  /// 媒体上传中：期间禁用附件按钮，避免并发上传把带宽吃满。
  final isUploading = false.obs;

  bool _hasMore = true;
  StreamSubscription? _sub;

  GroupChatController(this.group) {
    memberCount.value = group.memberCount;
  }

  /// 群聊里区分自己/他人消息必须用真实 userId，
  /// 不能像私聊那样靠"对端只有一个"推断。
  int get myId => auth.userProfile.value?.userId ?? 0;

  bool get hasMore => _hasMore;

  @override
  void onInit() {
    super.onInit();
    load();
    markRead();
    _sub = socket.events.listen(_onEvent);
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  void _onEvent(ChatEvent e) {
    if (e.type == 'group.message.new') {
      final m = ChatMessage.fromJson(e.data['message'] ?? {});
      if (m.groupId != group.groupId) return;
      // 去重：HTTP 发送返回的同一消息不再插入。
      messages.removeWhere((x) => x.id == m.id);
      messages.insert(0, m);
      markRead();
    } else if (e.type == 'group.updated') {
      final groupId = (e.data['groupId'] as num?)?.toInt() ?? 0;
      if (groupId != group.groupId) return;
      final action = (e.data['action'] ?? '') as String;
      final targetUserId = (e.data['targetUserId'] as num?)?.toInt() ?? 0;
      switch (action) {
        case 'kick' || 'leave':
          if (targetUserId == myId) {
            AppSnackbar.show('提示', action == 'kick' ? '你已被移出群聊' : '你已退出群聊');
            Get.back<void>();
          } else {
            _refreshMembers();
          }
        case 'disband':
          AppSnackbar.show('提示', '该群聊已被解散');
          Get.back<void>();
        case 'invite' || 'created':
          // 成员变动后拉取权威成员表：成员数准确，
          // 新成员的昵称/头像也能立即用于气泡渲染。
          _refreshMembers();
      }
    }
  }

  /// 拉取群信息刷新成员映射与成员数；失败静默（下次事件或重进页面再校准）。
  Future<void> _refreshMembers() async {
    try {
      final info = await ChatSDK.fetchGroupInfo(auth.userObj.value, group.groupId);
      members.value = {for (final m in info.members) m.userId: m};
      memberCount.value = info.memberCount;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {}
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final results = await Future.wait([
        ChatSDK.fetchGroupInfo(auth.userObj.value, group.groupId),
        ChatSDK.fetchGroupHistory(auth.userObj.value, group.groupId),
      ]);
      final info = results[0] as ChatGroupInfo;
      final list = results[1] as List<ChatMessage>;
      members.value = {for (final m in info.members) m.userId: m};
      memberCount.value = info.memberCount;
      messages.value = list;
      _hasMore = list.length >= 50;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || isLoadingMore.value || messages.isEmpty) return;
    isLoadingMore.value = true;
    try {
      final older = await ChatSDK.fetchGroupHistory(
        auth.userObj.value,
        group.groupId,
        beforeId: messages.last.id,
      );
      messages.addAll(older);
      _hasMore = older.length >= 50;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      AppSnackbar.error('加载失败', '请检查服务器连接');
    } finally {
      isLoadingMore.value = false;
    }
  }

  Future<void> send(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    try {
      final m = await ChatSDK.sendGroupMessage(auth.userObj.value, group.groupId, text);
      // 去重：socket 推送的同一消息不再插入。
      messages.removeWhere((x) => x.id == m.id);
      messages.insert(0, m);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    }
  }

  /// 上传并发送媒体消息（图片 / 视频），链路与私聊一致。
  Future<void> sendMedia(
    XFile file, {
    required bool isVideo,
    int width = 0,
    int height = 0,
    int durationMs = 0,
  }) async {
    if (isUploading.value) return;
    isUploading.value = true;
    try {
      final uploaded = await ChatSDK.uploadChatMedia(auth.userObj.value, file);
      final m = await ChatSDK.sendGroupMediaMessage(
        auth.userObj.value,
        group.groupId,
        uploaded.key,
        width: width,
        height: height,
        durationMs: durationMs,
        fileName: _mediaFileName(file),
      );
      // 去重：socket 推送的同一消息不再插入。
      messages.removeWhere((x) => x.id == m.id);
      messages.insert(0, m);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('发送失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isUploading.value = false;
    }
  }

  Future<void> markRead() async {
    try {
      await ChatSDK.markGroupRead(auth.userObj.value, group.groupId);
      final cleared = group.unreadCount;
      group.unreadCount = 0;
      if (cleared > 0) socket.clearUnreadMessages(cleared);
    } catch (_) {}
  }
}

/// 群信息页：群资料 + 成员列表 + 群主管理操作（拉人/踢人/解散）。
class GroupInfoController extends GetxController {
  final auth = Get.find<AuthService>();
  final socket = Get.find<ChatSocket>();

  final int groupId;
  final info = Rxn<ChatGroupInfo>();
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final isWorking = false.obs;
  StreamSubscription? _sub;

  /// 自己发起的退出类操作已自行导航，事件到达时不再重复 pop。
  bool _selfNavigated = false;

  GroupInfoController(this.groupId);

  int get myId => auth.userProfile.value?.userId ?? 0;

  bool get isOwner => info.value?.ownerId == myId;

  @override
  void onInit() {
    super.onInit();
    load();
    _sub = socket.events.listen((e) {
      if (e.type != 'group.updated') return;
      final gid = (e.data['groupId'] as num?)?.toInt() ?? 0;
      if (gid != groupId) return;
      final action = (e.data['action'] ?? '') as String;
      final targetUserId = (e.data['targetUserId'] as num?)?.toInt() ?? 0;
      final involvingMe =
          action == 'disband' || (targetUserId == myId && action != 'invite');
      if (involvingMe && !_selfNavigated) {
        AppSnackbar.show('提示', switch (action) {
          'kick' => '你已被移出群聊',
          'leave' => '你已退出群聊',
          _ => '该群聊已被解散',
        });
        Get.back<void>();
      } else if (!involvingMe) {
        // 其他成员变动：刷新成员列表。
        load();
      }
    });
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      info.value = await ChatSDK.fetchGroupInfo(auth.userObj.value, groupId);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      errorMessage.value = e is ApiException ? e.message : '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  /// 移出成员（仅群主可调用）。
  Future<void> kick(ChatGroupMember m) async {
    isWorking.value = true;
    try {
      await ChatSDK.groupKick(auth.userObj.value, groupId, m.userId);
      AppSnackbar.success('已移出', '${m.displayName} 已被移出群聊');
      await load();
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isWorking.value = false;
    }
  }

  /// 退出群聊。成功返回 true（视图据此关闭页面）。
  Future<bool> leave() async {
    isWorking.value = true;
    try {
      await ChatSDK.leaveGroup(auth.userObj.value, groupId);
      _selfNavigated = true;
      _fallbackBackIfOffline();
      return true;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isWorking.value = false;
    }
    return false;
  }

  /// 解散群聊。成功返回 true（视图据此关闭页面）。
  Future<bool> disband() async {
    isWorking.value = true;
    try {
      await ChatSDK.disbandGroup(auth.userObj.value, groupId);
      _selfNavigated = true;
      _fallbackBackIfOffline();
      return true;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    } finally {
      isWorking.value = false;
    }
    return false;
  }

  /// 长连接断开时收不到 group.updated 事件，自行退出页面兜底。
  void _fallbackBackIfOffline() {
    if (socket.status.value != ChatConnStatus.connected) {
      Get.back<void>();
    }
  }
}

/// 群成员拉入选择页：从好友中勾选未在群的用户（仅群主操作，服务端校验）。
class GroupInviteController extends GetxController {
  final auth = Get.find<AuthService>();

  final int groupId;
  /// 已在群的用户 ID，选择列表中排除。
  final Set<int> existingIds;
  final friends = <Friend>[].obs;
  final selected = <int>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  GroupInviteController(this.groupId, this.existingIds);

  List<Friend> get candidates =>
      friends.where((f) => !existingIds.contains(f.userId)).toList();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      friends.value = await ChatSDK.fetchFriends(auth.userObj.value);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  void toggle(int userId) {
    if (selected.contains(userId)) {
      selected.remove(userId);
    } else {
      selected.add(userId);
    }
  }

  /// 拉入成功返回实际添加人数（失败返回 -1）。
  Future<int> invite() async {
    if (selected.isEmpty) {
      AppSnackbar.show('提示', '请先选择要拉入的好友');
      return -1;
    }
    try {
      await ChatSDK.groupInvite(auth.userObj.value, groupId, selected.toList());
      AppSnackbar.success('已拉入', '已将 ${selected.length} 位好友拉入群聊');
      return selected.length;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (e) {
      AppSnackbar.error('操作失败', e is ApiException ? e.message : '请检查服务器连接');
    }
    return -1;
  }
}


/// 好友详情（私聊页右上角入口）。
///
/// 一次拉取对方简短资料、我设置的备注与双方共同群聊；
/// 备注保存成功后通过 [onRemarkSaved] 回调通知打开方（如私聊页同步标题）。
class FriendDetailController extends GetxController {
  final auth = Get.find<AuthService>();

  final int friendId;
  final detail = Rxn<ChatFriendDetail>();
  final isLoading = false.obs;
  final errorMessage = ''.obs;
  final isSavingRemark = false.obs;

  /// 备注保存成功回调，参数为新备注。
  void Function(String remark)? onRemarkSaved;

  FriendDetailController(this.friendId);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      detail.value = await ChatSDK.fetchFriendDetail(auth.userObj.value, friendId);
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接';
    } finally {
      isLoading.value = false;
    }
  }

  /// 保存备注；成功返回 true 并触发回调。
  Future<bool> saveRemark(String remark) async {
    isSavingRemark.value = true;
    try {
      final saved = await ChatSDK.setFriendRemark(auth.userObj.value, friendId, remark.trim());
      final d = detail.value;
      if (d != null) {
        detail.value = ChatFriendDetail(
          friend: d.friend,
          remark: saved,
          online: d.online,
          commonGroups: d.commonGroups,
        );
      }
      onRemarkSaved?.call(saved);
      return true;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
      return false;
    } on ApiException catch (e) {
      AppSnackbar.error('保存失败', e.message);
      return false;
    } catch (_) {
      AppSnackbar.error('保存失败', '请检查服务器连接');
      return false;
    } finally {
      isSavingRemark.value = false;
    }
  }
}
