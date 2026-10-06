// 本地媒体缓存的原生（Android/iOS/Windows/macOS/Linux）实现。
// 媒体以文件形式写入应用文档目录（沿用原 Cache.localFile 的路径规则），
// 渲染用 FileImage / VideoPlayerController.file，上传保持 fromPath 流式
// 读盘——大视频不会整体进内存。
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart' show FileImage, ImageProvider;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class CachedMedia {
  /// 缓存名（如 avatarCacheName / mediaCacheName 的返回值）。
  final String name;

  /// 本机缓存文件的完整路径。
  final String path;

  /// 公开构造：不做存在性检查，供测试或包装已知存在的文件使用；
  /// 常规读写一律走 [loadCachedMedia] / [writeCachedMedia]。
  CachedMedia({required this.name, required this.path});

  /// 图片渲染入口。同路径覆盖后需先 [evictImageCache] 再重建，
  /// 与原先直接持 FileImage 的语义一致。
  ImageProvider imageProvider() => FileImage(File(path));

  /// 视频播放入口（原生走 video_player 的官方平台后端）。
  VideoPlayerController createVideoController() =>
      VideoPlayerController.file(File(path));

  /// 清除该路径当前的解码缓存（ImageCache 以文件路径为键）。
  Future<void> evictImageCache() async {
    await FileImage(File(path)).evict();
  }

  /// 原生端没有 blob 之类的独立资源，无需释放。
  void release() {}
}

Future<CachedMedia?> loadCachedMedia(String name) async {
  final directory = await getApplicationDocumentsDirectory();
  final f = File('${directory.path}/$name');
  if (!f.existsSync()) return null;
  return CachedMedia(name: name, path: f.path);
}

Future<CachedMedia> writeCachedMedia(String name, Uint8List bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final f = File('${directory.path}/$name');
  // 路径不变、内容被覆盖：先清掉旧的解码缓存，避免 ImageCache 继续使用
  // 同一路径下的旧字节（原 ChatSDK.fetchUserAvatar 覆盖前的 evict 语义）。
  if (f.existsSync()) {
    await FileImage(f).evict();
  }
  await f.writeAsBytes(bytes, flush: true);
  return CachedMedia(name: name, path: f.path);
}

/// 组一个 multipart 上传分片。原生端 [MultipartFile.fromPath] 从磁盘流式
/// 读取（`package:http` 不会按扩展名推断 MIME，contentType 必须显式传）。
Future<http.MultipartFile> buildMediaPart(
  String field,
  XFile file,
  MediaType contentType,
) {
  return http.MultipartFile.fromPath(field, file.path, contentType: contentType);
}
