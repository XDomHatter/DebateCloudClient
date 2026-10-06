import 'package:debate_cloud/app/auth_service.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class ProfileController extends GetxController {
  final auth = Get.find<AuthService>();

  final isLoading = false.obs;
  final isSaving = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    // AuthService.init() may still be running; if the cached token is already
    // loaded but the profile never arrived (e.g. first launch offline), pull
    // it now.
    if (auth.isLoggedIn && auth.userProfile.value == null) {
      refreshProfile();
    }
  }

  Future<void> refreshProfile() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      await auth.refreshProfile();
      if (auth.userProfile.value == null) {
        errorMessage.value = '资料加载失败，请稍后重试';
      }
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } catch (_) {
      errorMessage.value = '加载失败，请检查服务器连接后重试';
    } finally {
      isLoading.value = false;
    }
  }

  /// Save nickname/bio. Returns true on success.
  Future<bool> saveProfile(String nickname, String bio) async {
    isSaving.value = true;
    try {
      final ok = await SDK.updateProfile(auth.userObj.value, nickname: nickname, bio: bio);
      if (ok) await auth.refreshProfile();
      return ok;
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
      return false;
    } catch (_) {
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    isSaving.value = true;
    try {
      await SDK.uploadAvatar(auth.userObj.value, picked);
      await auth.refreshProfile();
      AppSnackbar.show('提示', '头像已更新');
    } on AuthExpiredException catch (e) {
      await auth.handleAuthExpired(e);
    } on ApiException catch (e) {
      // 服务端拒绝上传的具体原因（格式不支持、超出大小等）。
      AppSnackbar.error('上传失败', e.message);
    } catch (_) {
      AppSnackbar.error('上传失败', '请检查服务器连接后重试');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> logout() => auth.logout();
}
