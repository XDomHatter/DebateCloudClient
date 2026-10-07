// 视频首帧海报的跨平台入口。
//
// 条件导入模式与 local_media.dart 相同：默认分支是原生实现，Web 编译
// 时（dart.library.js_interop 可用）切换到 Web 实现；两份实现的公开
// 签名必须一致。调用方只 import 本文件。
export 'video_poster_io.dart'
    if (dart.library.js_interop) 'video_poster_web.dart';
