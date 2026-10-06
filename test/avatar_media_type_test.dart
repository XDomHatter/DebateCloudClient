import 'package:debate_cloud/server_sdk/base.dart';
import 'package:flutter_test/flutter_test.dart';

// 回归：上传头像时 multipart 的 file 分片必须声明 image/* 类型。
// package:http 的 MultipartFile.fromPath 不会按扩展名推断，缺省是
// application/octet-stream，而服务端 ALLOWED_AVATAR_MIME 只放行
// image/jpeg|png|gif|webp —— 一旦回退成 octet-stream，客户端上传必定失败。
void main() {
  group('avatarMediaType', () {
    test('白名单内扩展名映射到对应的 image 类型', () {
      expect(avatarMediaType('/tmp/a.jpg').mimeType, 'image/jpeg');
      expect(avatarMediaType('/tmp/a.jpeg').mimeType, 'image/jpeg');
      expect(avatarMediaType('/tmp/a.JPG').mimeType, 'image/jpeg');
      expect(avatarMediaType('/tmp/a.png').mimeType, 'image/png');
      expect(avatarMediaType('/tmp/a.gif').mimeType, 'image/gif');
      expect(avatarMediaType('/tmp/a.webp').mimeType, 'image/webp');
    });

    test('无法识别的扩展名也不会回退成 application/octet-stream', () {
      const paths = ['/tmp/scaled_IMG_1234', '/tmp/a.heic', '/tmp/a', '/tmp/a.', 'a.png'];
      for (final path in paths) {
        expect(avatarMediaType(path).mimeType, startsWith('image/'), reason: path);
        expect(
          avatarMediaType(path).mimeType,
          isNot('application/octet-stream'),
          reason: path,
        );
      }
    });

    test('Windows 路径同样按最后一段扩展名解析', () {
      expect(avatarMediaType(r'C:\Users\x\cache\scaled_a.png').mimeType, 'image/png');
      expect(avatarMediaType(r'C:\Users\x\cache\a').mimeType, 'image/jpeg');
    });
  });
}
