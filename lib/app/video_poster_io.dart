// 视频首帧海报的原生实现：暂不支持截帧，一律返回 null。
//
// 原生端封面由调用方回退到现有的播放器取首帧路径
// （ChatVideoCover 的 VideoPlayerController 分支），行为与引入海报
// 机制之前完全一致。
import 'package:flutter/painting.dart' show ImageProvider;

import 'local_media.dart';

/// 尝试截取 [media]（一段视频）的首帧静态图；不支持时返回 null。
Future<ImageProvider?> createVideoPoster(CachedMedia media) async => null;
