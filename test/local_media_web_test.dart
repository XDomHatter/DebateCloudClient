@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:debate_cloud/app/local_media_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// 回归：Web 端 multipart 上传分片必须携带 filename（XFile.name）。
// package:http 的 MultipartFile.fromBytes 不传 filename 时，分片头没有
// `filename=` 属性，Jetty/Javalin 会把整个分片当普通表单字段而非文件，
// 服务端 uploadedFile("file") 取不到值，头像上传报 "file is required"。
void main() {
  group('buildMediaPart (web)', () {
    test('分片携带所选文件的 filename 与声明的 contentType', () async {
      final file = XFile.fromData(
        _bytes('hello'),
        name: 'avatar.png',
        mimeType: 'image/png',
      );

      final part = await buildMediaPart('file', file, MediaType('image', 'png'));

      expect(part.field, 'file');
      expect(part.filename, 'avatar.png');
      expect(part.contentType.mimeType, 'image/png');
    });

    test('序列化后的请求体包含 filename 属性（服务端识别文件分片的依据）', () async {
      final file = XFile.fromData(
        _bytes('hello'),
        name: 'avatar.png',
        mimeType: 'image/png',
      );
      final req = http.MultipartRequest('POST', Uri.parse('https://example.com/upload'))
        ..fields['body'] = '{}'
        ..files.add(await buildMediaPart('file', file, MediaType('image', 'png')));

      final body = utf8.decode(await req.finalize().toBytes(), allowMalformed: true);

      expect(body, contains('name="file"'));
      expect(body, contains('filename="avatar.png"'));
    });
  });
}

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
