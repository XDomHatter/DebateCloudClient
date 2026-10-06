import 'package:get/get.dart';

import 'cache.dart';

/// 聊天模块的本地偏好设置，落盘到 SharedPreferences（见 [Cache.p]）。
///
/// 目前只有「富文本渲染」开关：Markdown / LaTeX 是对历史消息的**重新解释**，
/// 老消息里原本用于「价格」「强调」的 `$`、`*` 会被渲染成公式或格式，
/// 因此必须给用户一个全局关闭的退路。
abstract final class ChatSettings {
  static const String _keyRichText = 'chat.rich_text_enabled';

  /// 是否渲染 Markdown / LaTeX。默认开启。
  static final RxBool richTextEnabled = true.obs;

  /// 在 [Cache.init] 之后调用，读回上次的选择。
  static Future<void> load() async {
    final p = Cache.p;
    if (p == null) return;
    richTextEnabled.value = p.getBool(_keyRichText) ?? true;
  }

  static Future<void> setRichTextEnabled(bool value) async {
    richTextEnabled.value = value;
    await Cache.p?.setBool(_keyRichText, value);
  }
}
