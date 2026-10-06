/// 本地媒体缓存的平台无关入口。
///
/// 整个 app 以 [CachedMedia] 作为"下载到本地的媒体"（头像、聊天图片/视频）的
/// 流通类型，渲染与上传的平台差异全部收在实现文件里，调用方（SDK / UI）
/// 不出现任何 `dart:io` 类型：
///
/// - 有 `dart:io` 的平台（Android/iOS/Windows/macOS/Linux）用
///   `local_media_io.dart`：媒体写入应用文档目录，渲染用
///   `FileImage` / `VideoPlayerController.file`，上传走 `fromPath` 流式读盘。
/// - Web 用 `local_media_web.dart`：浏览器没有文件系统，字节保存在会话内存
///   （刷新页面后重新向服务端拉取），渲染用 `MemoryImage`，视频通过
///   `blob:` URL 交给 video_player 的官方 Web 后端，上传走 `fromBytes`。
///
/// 两个实现的公开 API 必须保持一致。
///
/// **默认分支必须是 io 实现**：静态分析不求值条件表达式，固定取默认分支，
/// 而 `flutter test` / 桌面开发都在 io 语义下进行；Web 构建时
/// `dart.library.js_interop` 为真，编译器换成 Web 实现。
library;

import 'local_media_io.dart' if (dart.library.js_interop) 'local_media_web.dart';

export 'local_media_io.dart' if (dart.library.js_interop) 'local_media_web.dart';
