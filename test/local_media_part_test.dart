import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// 回归（VM 等价验证）：multipart 上传分片必须携带 filename，服务端
// （Jetty/Javalin）靠分片头的 `filename=` 属性区分文件与普通表单字段。
// Web 端 buildMediaPart（local_media_web.dart）此前用 fromBytes 时漏传
// filename，分片被服务端当成字段，头像上传报 "file is required"。
// multipart 的序列化由 package:http 纯 Dart 实现，Web 与原生共用，
// 这里在 VM 上直接验证两种写法的分片头差异。
http.MultipartRequest _requestWith(http.MultipartFile part) {
  return http.MultipartRequest('POST', Uri.parse('https://example.com/upload'))
    ..fields['body'] = '{}'
    ..files.add(part);
}

void main() {
  group('MultipartFile.fromBytes 的 filename（web 端上传分片机制）', () {
    test('带 filename：分片头包含 filename 属性，服务端识别为文件', () async {
      final part = http.MultipartFile.fromBytes(
        'file',
        utf8.encode('hello'),
        filename: 'avatar.png',
        contentType: MediaType('image', 'png'),
      );
      final body = utf8.decode(
        await _requestWith(part).finalize().toBytes(),
        allowMalformed: true,
      );
      expect(body, contains('name="file"'));
      expect(body, contains('filename="avatar.png"'));
    });

    test('不带 filename：分片头无 filename 属性，服务端将判定缺少上传文件', () async {
      final part = http.MultipartFile.fromBytes(
        'file',
        utf8.encode('hello'),
        contentType: MediaType('image', 'png'),
      );
      final body = utf8.decode(
        await _requestWith(part).finalize().toBytes(),
        allowMalformed: true,
      );
      expect(body, contains('name="file"'));
      expect(body, isNot(contains('filename=')));
    });
  });
}
