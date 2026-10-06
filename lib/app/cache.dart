import 'package:shared_preferences/shared_preferences.dart';

/// 应用级键值存储入口（shared_preferences：原生为系统偏好，Web 为
/// localStorage）。二进制媒体缓存见 local_media.dart，按平台分流。
class Cache {
  static SharedPreferences? p;

  static Future<void> init() async {
    p = await SharedPreferences.getInstance();
  }
}
