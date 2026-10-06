// Windows / Linux 没有 video_player 的官方实现（其官方只支持
// Android / iOS / macOS / Web），直接使用会退化为占位实现并抛
// UnimplementedError。这里给这两个平台挂上 media_kit 后端，
// 之后仍按 video_player 的常规 API 使用，无需改动播放代码。
// 其余平台保持官方实现（Android 用 ExoPlayer，体积与功耗更优）。
//
// 此文件只在有 dart:io 的平台参与编译（见 main.dart 的条件导入），
// Web 构建不会引入 media_kit。
import 'package:video_player_media_kit/video_player_media_kit.dart';

void initVideoBackend() {
  VideoPlayerMediaKit.ensureInitialized(windows: true, linux: true);
}
