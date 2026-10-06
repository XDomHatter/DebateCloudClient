// 聊天媒体（图片 / 视频）的回归测试。
//
// 覆盖三层：
// 1) 纯函数：上传用的 MediaType 推断、本地缓存文件名推导；
// 2) 消息解析：type / payload 从服务端 JSON 还原（服务端 v9 起支持）；
// 3) 渲染与交互：媒体气泡拿不到字节时降级为占位而非崩溃；
//    附件按钮位于输入区 TapRegion 分组内——否则桌面端点它会丢焦点。
//
// 必须使用真实 AppTheme：裸 ThemeData 会漏掉项目按钮主题相关的崩溃
// （按钮主题 minimumSize 宽度为无穷大，裸放进 Row 会直接崩）。
import 'package:debate_cloud/app/app_theme.dart';
import 'package:debate_cloud/app/auth_service.dart';
// 测试只在 VM 上运行（dart:io 必然可用），直接导入 io 实现；
// 走 local_media.dart 门面的话，静态分析会按 Web 变体解析，
// CachedMedia 的 path 构造会被误报为不存在。
import 'package:debate_cloud/app/local_media_io.dart';
import 'package:debate_cloud/routed_apps/chat/chat_widgets.dart';
import 'package:debate_cloud/server_sdk/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// 构造一条媒体消息，默认图片。
ChatMessage mediaMessage({
  String type = 'image',
  Map<String, dynamic> payload = const {
    'key': 'chat/abc.png',
    'kind': 'image',
    'width': 800,
    'height': 600,
  },
}) {
  return ChatMessage(
    id: 1,
    senderId: 2,
    receiverId: 1,
    content: type == 'video' ? '[视频]' : '[图片]',
    type: type,
    payload: payload,
    createdAt: '2026-09-16 12:00:00',
    read: false,
  );
}

/// 挂载单个媒体气泡。
///
/// 不能用 pumpAndSettle：占位里的 CircularProgressIndicator 是无限动画，
/// pumpAndSettle 会一直等到超时。
Future<void> pumpBubble(WidgetTester tester, ChatMessage m) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ChatMediaBubble(message: m, maxWidth: 200)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    Get.reset();
    // 匿名 AuthService：ChatSDK.fetchChatMedia 会直接返回 null，测试不触网。
    Get.put(AuthService());
  });

  tearDown(Get.reset);

  group('chatMediaType', () {
    test('按扩展名推断图片类型', () {
      expect(chatMediaType('a/b/photo.PNG').mimeType, 'image/png');
      expect(chatMediaType('photo.jpg').mimeType, 'image/jpeg');
      expect(chatMediaType('photo.webp').mimeType, 'image/webp');
    });

    test('按扩展名推断视频类型', () {
      expect(chatMediaType('clip.mp4').mimeType, 'video/mp4');
      expect(chatMediaType('clip.MOV').mimeType, 'video/quicktime');
      expect(chatMediaType('clip.webm').mimeType, 'video/webm');
    });

    test('未知扩展名回退为 image/jpeg（服务端会再按扩展名单独校验）', () {
      expect(chatMediaType('noext').mimeType, 'image/jpeg');
      expect(chatMediaType('file.xyz').mimeType, 'image/jpeg');
    });
  });

  group('mediaCacheName', () {
    test('去掉目录部分并加前缀，避免与其他缓存文件重名', () {
      expect(mediaCacheName('chat/ab12cd.png'), 'media_ab12cd.png');
      expect(mediaCacheName('plain.png'), 'media_plain.png');
    });
  });

  group('媒体消息解析', () {
    test('type 与 payload 从服务端 JSON 还原', () {
      final m = ChatMessage.fromJson({
        'id': 7,
        'senderId': 3,
        'receiverId': 4,
        'content': '[图片]',
        'type': 'image',
        'payload': {
          'key': 'chat/x.jpg',
          'width': 1024,
          'height': 768,
          'size': 2048,
        },
        'createdAt': '2026-09-16 12:00:00',
        'read': false,
      });
      expect(m.type, 'image');
      expect(m.payload['key'], 'chat/x.jpg');
      expect(m.payload['width'], 1024);
    });

    test('payload 缺失时按空对象处理，不抛异常', () {
      final m = ChatMessage.fromJson({
        'id': 8,
        'senderId': 3,
        'receiverId': 4,
        'content': '[视频]',
        'type': 'video',
        'createdAt': '2026-09-16 12:00:00',
        'read': false,
      });
      expect(m.type, 'video');
      expect(m.payload, isEmpty);
    });
  });

  group('ChatMediaBubble', () {
    testWidgets('拿不到媒体字节时降级为占位，不抛异常', (tester) async {
      await pumpBubble(tester, mediaMessage());
      expect(find.text('媒体加载失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('payload 缺 key 时同样降级为占位', (tester) async {
      await pumpBubble(tester, mediaMessage(payload: const {}));
      expect(find.text('媒体加载失败'), findsOneWidget);
    });

    testWidgets('视频消息走视频分支且不抛异常', (tester) async {
      await pumpBubble(tester, mediaMessage(type: 'video'));
      expect(find.byType(ChatMediaBubble), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('视频初始化失败（复现 Windows 无平台实现的路径）', () {
    // 测试环境下 VideoPlayerPlatform 同样是占位实现：create() 同步抛
    // UnimplementedError，且 VideoPlayerController.dispose() 会因内部
    // Completer 永不完成而永久挂起——与 Windows 上的表现完全一致。
    // 这两条用例因此直接守护「失败态必须显示出来」这一修复点：
    // 一旦错误分支里先 await dispose()，界面就会停在加载动画上，断言即失败。

    testWidgets('ChatVideoCover 给出失败态而不是无限加载', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ChatVideoCover(
              // 指向不存在的路径：createVideoController 仍会在 initialize()
              // 时走占位平台实现并抛异常，与原 File 用例的失败路径一致。
              media: CachedMedia(name: 'clip.mp4', path: 'C:/nonexistent/clip.mp4'),
              width: 200,
              height: 150,
            ),
          ),
        ),
      );
      // 不能用 pumpAndSettle：修复失效时界面是无限动画，会一直等到超时。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('无法预览视频'), findsOneWidget);
      // 放掉 _safeDisposeVideo 的兜底超时定时器：dispose 挂起是预期行为，
      // 超时兜底正是为此存在；但未触发的定时器会让测试收尾的
      // '!timersPending' 断言失败。
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('ChatMediaViewerPage 给出失败态而不是无限加载', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ChatMediaViewerPage(
            media: CachedMedia(name: 'clip.mp4', path: 'C:/nonexistent/clip.mp4'),
            isVideo: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('视频无法播放'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('ChatMediaPickerButton', () {
    testWidgets('位于输入区 TapRegion 分组内（否则桌面端点击会丢焦点）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ChatMediaPickerButton(enabled: true, onPicked: (_, _) {}),
          ),
        ),
      );
      final region = tester.widget<TextFieldTapRegion>(
        find
            .ancestor(
              of: find.byType(IconButton),
              matching: find.byType(TextFieldTapRegion),
            )
            .first,
      );
      expect(region.groupId, chatInputTapGroupId);
    });

    testWidgets('放在 Row 中不触发无穷宽约束崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Row(
              children: [
                ChatMediaPickerButton(enabled: true, onPicked: (_, _) {}),
                const Expanded(child: TextField()),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('上传中禁用按钮，避免并发上传', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ChatMediaPickerButton(
              enabled: true,
              isUploading: true,
              onPicked: (_, _) {},
            ),
          ),
        ),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('不可发送时禁用按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ChatMediaPickerButton(enabled: false, onPicked: (_, _) {}),
          ),
        ),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });
  });
}
