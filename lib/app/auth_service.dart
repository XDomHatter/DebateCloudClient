import 'package:debate_cloud/app/cache.dart';
import 'package:debate_cloud/server_sdk/base.dart';
import 'package:debate_cloud/server_sdk/user.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:debate_cloud/widgets/app_snackbar.dart';

class AuthService extends GetxService {
  /// Observable auth state; views rebuild on login/logout.
  final userObj = UserObj(token: null).obs;

  /// Observable profile; null when logged out or not loaded yet.
  final userProfile = Rxn<UserProfile>();

  bool get isLoggedIn => !userObj.value.isAnonymous;

  Future<void> init() async {
    userObj.value = UserObj(token: Cache.p!.getString("jwtToken"));
    if (!isLoggedIn) return;

    try {
      // Ask the server to confirm the cached token is still valid before
      // loading any profile data.
      await SDK.verifySession(userObj.value);
      await refreshProfile();
    } on AuthExpiredException catch (e) {
      await handleAuthExpired(e);
    } catch (e) {
      // Server unreachable etc. — keep the session; the profile tab will
      // surface the error when the user opens it.
      debugPrint('Session verification failed: $e');
    }
  }

  Future<void> refreshProfile() async {
    if (!isLoggedIn) return;
    try {
      final profile = await SDK.fetchUserProfile(userObj.value);
      if (profile == null) return;
      profile.avatar = await SDK.fetchAvatar(userObj.value);
      if (profile.avatar != null) {
        // The cached avatar (file path on native, bytes on web) stays the
        // same key across uploads, so drop the stale decoded image and let
        // the next build read the new content.
        await profile.avatar!.evictImageCache();
      }
      userProfile.value = profile;
    } on AuthExpiredException catch (e) {
      await handleAuthExpired(e);
    }
  }

  Future<void> login(UserObj t) async {
    userObj.value = t;
    await Cache.p?.setString('jwtToken', t.token!);
    await refreshProfile();
  }

  Future<void> logout() async {
    // Only reassign userObj when actually leaving a session: UserObj has no
    // ==, so assigning a fresh anonymous instance would fire userObj
    // listeners even when already logged out and re-trigger their loads.
    if (!userObj.value.isAnonymous) {
      userObj.value = UserObj(token: null);
    }
    userProfile.value = null;
    await Cache.p?.remove('jwtToken');
  }

  /// The server rejected the current token (missing, invalid or expired).
  /// Clears the local session and notifies the user so the UI can fall back
  /// to the guest/login state.
  ///
  /// [e] carries the token the failed request was sent with. A 404 that
  /// arrives after the user already switched sessions (e.g. an in-flight
  /// request from before a re-login) must not clear the new session, so a
  /// mismatch is ignored silently.
  Future<void> handleAuthExpired([AuthExpiredException? e]) async {
    final failedToken = e?.token;
    if (failedToken != null && failedToken != userObj.value.token) return;
    await logout();
    // The UI tree may not be ready when this runs during app startup, so
    // defer the notification until after the current frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Get.context != null) {
        AppSnackbar.error('登录已过期', '请重新登录');
      }
    });
  }
}
