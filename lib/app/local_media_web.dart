// 本地媒体缓存的 Web 实现。
// 浏览器没有文件系统，媒体字节保存在会话内存里（刷新页面后重新向服务端
// 拉取，服务端始终是数据源）；渲染用 MemoryImage，视频通过 blob: URL 交给
// video_player 的官方 Web 后端播放，上传用 fromBytes。
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/painting.dart' show ImageProvider, MemoryImage;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// 会话级内存缓存：缓存名 -> 字节。容量管理（LRU 上限 / IndexedDB 持久化）
/// 留作后续迭代。
final Map<String, Uint8List> _cacheStore = <String, Uint8List>{};

class CachedMedia {
  /// 缓存名（与原生端同名同值，方便排查）。
  final String name;

  final Uint8List? bytes;

  /// 同一份字节生成的 blob URL 只建一次，[release] 负责回收。
  String? _blobUrl;

  CachedMedia._(this.name, this.bytes);

  /// 公开构造：供测试或特殊场景直接包一份已有字节；常规读写一律走
  /// [loadCachedMedia] / [writeCachedMedia]。
  CachedMedia.inMemory({required this.name, required this.bytes});

  /// 图片渲染入口。
  ImageProvider imageProvider() => MemoryImage(bytes!);

  /// 视频播放入口。video_player 的 Web 后端是 <video> 元素，blob: URL
  /// 可以直接作为其 src，播放器逻辑仍按常规 API 编写。
  VideoPlayerController createVideoController() =>
      VideoPlayerController.networkUrl(Uri.parse(_blobUrlFor()));

  String _blobUrlFor() {
    final existing = _blobUrl;
    if (existing != null) return existing;
    return _blobUrl = _createBlobUrl(bytes!);
  }

  /// Web 端 MemoryImage 以字节对象为缓存键，写入方替换字节后旧条目
  /// 自然失效；这里按语义清一次，保持与原生端对齐。
  Future<void> evictImageCache() async {
    final b = bytes;
    if (b != null) await MemoryImage(b).evict();
  }

  /// 释放已生成的 blob URL（UI 在销毁视频播放器时调用）。
  void release() {
    final url = _blobUrl;
    _blobUrl = null;
    if (url != null) web.URL.revokeObjectURL(url);
  }
}

String _createBlobUrl(Uint8List bytes) {
  final parts = <JSAny>[bytes.toJS];
  return web.URL.createObjectURL(web.Blob(parts.toJS));
}

Future<CachedMedia?> loadCachedMedia(String name) async {
  final bytes = _cacheStore[name];
  if (bytes == null) return null;
  return CachedMedia._(name, bytes);
}

Future<CachedMedia> writeCachedMedia(String name, Uint8List bytes) async {
  _cacheStore[name] = bytes;
  return CachedMedia._(name, bytes);
}

/// 组一个 multipart 上传分片。Web 端没有可读路径，直接把选择器给出的
/// 字节交给 `fromBytes`（XFile.readAsBytes 在 Web 上从 blob 拉取）。
Future<http.MultipartFile> buildMediaPart(
  String field,
  XFile file,
  MediaType contentType,
) async {
  return http.MultipartFile.fromBytes(
    field,
    await file.readAsBytes(),
    contentType: contentType,
  );
}
