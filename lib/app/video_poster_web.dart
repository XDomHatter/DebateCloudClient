// 视频首帧海报的 Web 实现。
//
// 列表里每个可见视频消息若都创建 VideoPlayerController（Web 后端即
// <video> 元素并解码视频）只为显示第 0 帧，移动端滚动时开销巨大。
// 这里用一个隐藏 <video> 把首帧截成静态图并按缓存名复用，封面不再
// 挂播放器；任何一步失败都返回 null，由调用方回退到播放器路径。
//
// blob: URL 由本会话字节创建，与页面同源，canvas 不会被污染，
// toDataURL 不会抛 SecurityError。
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/painting.dart' show ImageProvider, MemoryImage;
import 'package:web/web.dart' as web;

// 直接依赖 Web 实现本身：本文件只在 Web 编译里生效，且静态分析按默认
// （io）语义解析条件入口，经 local_media.dart 转引拿不到 Web 端的类型。
import 'local_media_web.dart';

/// 单帧截取整体超时：宁可回退播放器封面，也不要无限等。
const Duration _captureTimeout = Duration(seconds: 6);

/// 海报缓存：缓存名 -> 首帧图。列表滚动往返不重复截帧。
final Map<String, ImageProvider> _posterCache = <String, ImageProvider>{};

/// 海报缓存上限：截帧是一次性成本，超限整表清空即可，无需 LRU。
const int _posterCacheCapacity = 32;

/// 截取 [media]（一段视频）的首帧静态图；失败返回 null。
Future<ImageProvider?> createVideoPoster(CachedMedia media) async {
  final hit = _posterCache[media.name];
  if (hit != null) return hit;
  try {
    final poster = await _captureFirstFrame(media).timeout(_captureTimeout);
    if (poster == null) return null;
    if (_posterCache.length >= _posterCacheCapacity) _posterCache.clear();
    _posterCache[media.name] = poster;
    return poster;
  } catch (_) {
    return null;
  }
}

Future<ImageProvider?> _captureFirstFrame(CachedMedia media) async {
  final video = web.HTMLVideoElement()
    ..muted = true
    ..playsInline = true
    ..preload = 'auto';
  // 隐藏挂载到文档：个别浏览器对脱离 DOM 的媒体元素不保证解码。
  video.style.display = 'none';
  web.document.body?.appendChild(video);
  try {
    // loadeddata = 首帧可用；error 使等待立即失败而不是白等超时。
    final loaded = _waitEventOnce(video, 'loadeddata');
    final errored = _waitEventOnce(video, 'error');
    video.src = media.ensureBlobUrl();
    final ok = await Future.any([loaded, errored]);
    if (!ok) return null;
    if (video.videoWidth <= 0 || video.videoHeight <= 0) return null;

    // 跳到 0.1s：不少容器首帧是黑帧。等不到 seeked 也无妨，
    // 直接截当前帧。
    final seeked = _waitEventOnce(video, 'seeked');
    video.currentTime = 0.1;
    await seeked;

    final width = video.videoWidth;
    final height = video.videoHeight;
    final scale = width > _posterMaxWidth ? _posterMaxWidth / width : 1.0;
    final canvas = web.HTMLCanvasElement()
      ..width = (width * scale).round()
      ..height = (height * scale).round();
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);
    const prefix = 'data:image/jpeg;base64,';
    if (!dataUrl.startsWith(prefix)) return null;
    return MemoryImage(base64Decode(dataUrl.substring(prefix.length)));
  } finally {
    // 释放解码器与 DOM 挂载；共享的 blob URL 归 media 所有，不在这里
    // revoke（media.release 才负责回收）。
    video.removeAttribute('src');
    video.load();
    video.remove();
  }
}

/// 海报最长边（宽向）上限：封面气泡最大几百逻辑像素，640 足够。
const int _posterMaxWidth = 640;

/// 等待 [video] 派发 [type] 事件；超时返回 false。整体 [_captureTimeout]
/// 由上层兜底，这里用同一时限防单个事件挂死。
Future<bool> _waitEventOnce(web.HTMLVideoElement video, String type) {
  final completer = Completer<bool>();
  late final JSFunction listener;
  listener = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(true);
  }).toJS;
  video.addEventListener(type, listener);
  return completer.future
      .then<bool>((ok) {
        video.removeEventListener(type, listener);
        return ok;
      })
      .timeout(_captureTimeout, onTimeout: () {
        video.removeEventListener(type, listener);
        // 事件迟到时 completer 已无人等待，complete 调用被上面的
        // isCompleted 守卫拦下，不会抛 StateError。
        if (!completer.isCompleted) completer.complete(false);
        return false;
      });
}
