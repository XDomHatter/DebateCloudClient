import 'dart:collection';

import 'package:debate_cloud/app/app_design.dart';
import 'package:debate_cloud/app/chat_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

/// 聊天文本：Markdown / LaTeX 的渲染与纯文本化。
///
/// 服务端只把消息当纯字符串存（无 HTML、无富文本协议），所以富文本是
/// **纯客户端的渲染层解释**，不需要改协议、不需要 schema 迁移，
/// 老版本客户端看到的仍是源码文本。
abstract final class ChatMarkdown {
  /// 单个公式的最大字符数。超长公式按普通文本展示，避免解析拖慢列表。
  static const int maxTexLength = 300;

  /// 富文本渲染的最大字符数。超过则整体降级为纯文本。
  static const int maxRenderLength = 4000;

  /// 代码围栏（含语言标识与内容）。
  static final RegExp _fence = RegExp(r'```[\s\S]*?```');

  /// 行内代码。
  static final RegExp _inlineCode = RegExp(r'`[^`\n]+`');

  /// 疑似富文本的特征：标题 / 引用 / 列表 / 表格 / 强调 / 链接 / 公式。
  static final RegExp _richHint = RegExp(
    r'^ *(?:#{1,6} |>|[-+*] |\d+[.)] )|[#*`_~\[\]|]|\\\(|\\\[|\$',
    multiLine: true,
  );

  /// LRU 缓存容量：list 滚动时每条消息都跑一次 prepare/strip，
  /// 缓存命中能让正则扫描几乎归零；上限避免长会话时无界增长。
  /// （按字符串去重，最坏 200 条 × 4000 字 ≈ 1.6 MB 可控。）
  static const int _cacheCapacity = 200;

  static final _LruCache _prepareCache = _LruCache(_cacheCapacity);
  static final _LruCache _stripCache = _LruCache(_cacheCapacity);

  /// 仅测试使用——把两个缓存清空，避免用例之间互相污染。
  @visibleForTesting
  static void debugClearCaches() {
    _prepareCache.clear();
    _stripCache.clear();
  }

  /// 是否值得走 Markdown 渲染。绝大多数消息是纯文本，这条短路能省掉解析开销。
  static bool looksRich(String src) => _richHint.hasMatch(src);

  /// 渲染前的清洗：把**未配对**的 `$` 转义成字面量。
  ///
  /// 历史消息里的 `$100`、半句 `x = $a` 会被引擎当成公式起止符，
  /// 导致整条消息错乱。这里的规则是：
  /// - `$$…$$` 成对且长度合规 → 保留（允许跨行）；
  /// - `$…$` 成对、非空、**不跨行**且长度合规 → 保留；
  /// - 其余所有 `$` → 转义为 `\$`，按字面量显示；
  /// - 代码块与行内代码内部**完全不处理**（先抠出来再回填）。
  static String prepare(String src) {
    if (!src.contains(r'$')) return src;
    final hit = _prepareCache.get(src);
    if (hit != null) return hit;
    final out = _prepareRaw(src);
    _prepareCache.put(src, out);
    return out;
  }

  /// `prepare` 的纯函数逻辑（无缓存）；便于在隔离上下文里直接测试。
  static String _prepareRaw(String src) {
    final slots = <String>[];
    final masked = src
        .replaceAllMapped(_fence, (m) => _mask(slots, m.group(0)!))
        .replaceAllMapped(_inlineCode, (m) => _mask(slots, m.group(0)!));

    final buf = StringBuffer();
    var i = 0;
    while (i < masked.length) {
      final ch = masked[i];
      // 占位片段原样搬运，不做任何公式判断。
      if (ch == '\u0000') {
        final end = masked.indexOf('\u0000', i + 1);
        buf.write(masked.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      if (ch != r'$') {
        buf.write(ch);
        i += 1;
        continue;
      }
      final isBlock = i + 1 < masked.length && masked[i + 1] == r'$';
      final delim = isBlock ? r'$$' : r'$';
      final bodyStart = i + delim.length;
      final end = masked.indexOf(delim, bodyStart);
      final body = end < 0 ? null : masked.substring(bodyStart, end);
      final paired = body != null &&
          body.trim().isNotEmpty &&
          body.length <= maxTexLength &&
          (isBlock || !body.contains('\n'));
      if (paired) {
        buf.write(delim + body + delim);
        i = end + delim.length;
      } else {
        // 未闭合：降级为字面量，绝不让半个公式吞掉后面的正文。
        buf.write(r'\$');
        i += 1;
      }
    }
    return _unmask(slots, buf.toString());
  }

  /// 去掉 Markdown 标记，得到适合单行摘要展示的纯文本。
  ///
  /// 会话列表 / 通知卡片用：它们拿到的是服务端原样下发的 `content`，
  /// 不处理就会显示 `**粗体**`、`$x^2$` 这类源码。
  static String strip(String src) {
    if (src.isEmpty) return src;
    final hit = _stripCache.get(src);
    if (hit != null) return hit;
    final out = _stripRaw(src);
    _stripCache.put(src, out);
    return out;
  }

  /// `strip` 的纯函数逻辑。
  static String _stripRaw(String src) {
    final out = <String>[];
    var inFence = false;
    for (final raw in src.split('\n')) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      var s = raw;
      s = s.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
        (m) => (m.group(1) ?? '').trim().isEmpty ? '[图片]' : m.group(1)!.trim(),
      );
      s = s.replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      );
      s = s.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
      s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*'), '');
      s = s.replaceAll(RegExp(r'^\s*>+\s*'), '');
      s = s.replaceAll(RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+'), '');
      // 表格分隔行 |---|---| 直接丢弃。
      if (RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$').hasMatch(s)) continue;
      s = s.replaceAll('|', ' ');
      // 公式保留内容、丢掉定界符：$x^2$ → x^2
      s = s.replaceAllMapped(
        RegExp(r'\$\$?([^$]*)\$\$?'),
        (m) => (m.group(1) ?? '').trim(),
      );
      s = s.replaceAll(r'\(', ' ').replaceAll(r'\)', ' ');
      s = s.replaceAll('**', '').replaceAll('~~', '').replaceAll('`', '');
      // 摘要里 `*` 基本只剩强调用途，直接去掉；Dart RegExp 不支持后行断言，
      // 这里不做「只删包围型星号」的精细判断。
      s = s.replaceAll('*', '');
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out.join(' ');
  }

  static String _mask(List<String> slots, String s) {
    slots.add(s);
    return '\u0000${slots.length - 1}\u0000';
  }

  static String _unmask(List<String> slots, String text) =>
      text.replaceAllMapped(
        RegExp('\u0000(\\d+)\u0000'),
        (m) => slots[int.parse(m.group(1)!)],
      );
}

/// 简单 LRU：用 LinkedHashMap 的插入顺序语义，命中时挪到末尾，
/// 容量超出时淘汰最久未访问的条目。O(1) put/get。
class _LruCache {
  _LruCache(this.capacity);

  final int capacity;
  final LinkedHashMap<String, String> _map = LinkedHashMap();

  String? get(String key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v;
    return v;
  }

  void put(String key, String value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();

  int get length => _map.length;
}

/// 聊天消息正文：能渲染 Markdown + LaTeX，也能在开关关闭时退回纯文本。
///
/// 三处气泡（单聊、群聊、群系统提示）应当统一用它，避免样式漂移。
class ChatRichText extends StatelessWidget {
  const ChatRichText(
    this.content, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.enabled = true,
  });

  final String content;
  final TextStyle? style;
  final TextAlign? textAlign;

  /// 摘要场景可限制行数；气泡内一般不限制。
  final int? maxLines;
  final TextOverflow? overflow;

  /// 调用点级别的开关（如系统提示行不参与富文本）。
  final bool enabled;

  /// 超过这个长度的气泡默认折叠，按需展开。
  ///
  /// 服务端上限 4000 字，没有这个保护，一条带表格和公式的论证会顶掉整个屏幕。
  static const int _foldThreshold = 600;
  static const double _foldedMaxHeight = 240;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return _plain();
    // 跟随全局设置变化即时重绘。
    return Obx(() {
      final rich = ChatSettings.richTextEnabled.value &&
          content.length <= ChatMarkdown.maxRenderLength &&
          ChatMarkdown.looksRich(content);
      if (!rich) return _plain();
      final body = _renderMarkdown(context);
      if (content.length <= _foldThreshold) return body;
      return _Foldable(
        maxHeight: _foldedMaxHeight,
        contentLength: content.length,
        child: body,
      );
    });
  }

  Widget _renderMarkdown(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // 必须中和本项目的「按钮撑满」约定：AppTheme 把四类按钮的 minimumSize
      // 设为 Size.fromHeight(48)（最小宽 = 无穷大），而 gpt_markdown 的复制按钮
      // 等内部控件被放进 Row 里——Row 对非 flex 子不施加宽度约束，
      // 两者叠加就会抛 "BoxConstraints forces an infinite width"（见
      // code_field.dart 的 TextButton）。这里只在富文本子树内压成有界尺寸。
      data: theme.copyWith(
        textButtonTheme:
            TextButtonThemeData(style: _bounded(theme.textButtonTheme.style)),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: _bounded(theme.elevatedButtonTheme.style),
        ),
        filledButtonTheme:
            FilledButtonThemeData(style: _bounded(theme.filledButtonTheme.style)),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: _bounded(theme.outlinedButtonTheme.style),
        ),
        iconButtonTheme:
            IconButtonThemeData(style: _bounded(theme.iconButtonTheme.style)),
      ),
      child: GptMarkdown(
        ChatMarkdown.prepare(content),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        // 聊天里 `$x^2$` 比 `\(x^2\)` 自然得多。
        useDollarSignsForLatex: true,
        // 已落库的消息是静态内容，不要打字机动画。
        isStreaming: false,
        animation: GptMarkdownAnimation.none,
        styleSheet: const GptMarkdownStyleSheet(
          codeBlock: CodeBlockStyle(
            showCopyButton: true,
            borderRadius: Radius.circular(AppDesign.radiusM),
          ),
          latex: LatexStyle(scrollBlockHorizontally: true),
          table: TableStyle(cellPadding: EdgeInsets.all(6)),
        ),
        onLinkTap: (url, _) => openChatLink(url),
      ),
    );
  }

  /// 保留主题其余属性，只把最小尺寸改成有界值。
  static ButtonStyle _bounded(ButtonStyle? base) => (base ?? const ButtonStyle())
      .copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 34)));

  Widget _plain() => Text(
        content,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: true,
      );
}

/// 长消息折叠：折叠态不渲染 Markdown 内容，避免 gpt_markdown 在受限空间里
/// 反复 layout 大段渲染（曾导致列外溢 100+ 像素）。展开态才真正挂载 [child]。
///
/// 局部 State，列表项重建后回到折叠态——聊天列表里极少出现对同一条长消息
/// 反复展开/收起，跨项记忆带来的复杂度不值。
class _Foldable extends StatefulWidget {
  const _Foldable({
    required this.child,
    required this.maxHeight,
    required this.contentLength,
  });
  final Widget child;
  final double maxHeight;
  final int contentLength;

  @override
  State<_Foldable> createState() => _FoldableState();
}

class _FoldableState extends State<_Foldable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded)
          widget.child
        else
          Container(
            height: widget.maxHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppDesign.radiusM),
            ),
            child: Text(
              '消息较长（${widget.contentLength} 字），点击展开',
              style: text.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? '收起' : '展开'),
          ),
        ),
      ],
    );
  }
}

/// 打开消息里的链接：只放行 http/https/mailto，其余协议一律拦截。
///
/// 失败时退化为「复制到剪贴板 + 提示」，不让用户面对一个点了没反应的链接。
Future<void> openChatLink(String url) async {
  final uri = Uri.tryParse(url.trim());
  final scheme = uri?.scheme.toLowerCase() ?? '';
  const allowed = {'http', 'https', 'mailto'};
  if (uri == null || !allowed.contains(scheme)) {
    AppSnackbar.error('链接已拦截', '不支持的链接协议');
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return;
    throw StateError('launchUrl returned false');
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    AppSnackbar.error('无法打开链接', '已复制到剪贴板');
  }
}
