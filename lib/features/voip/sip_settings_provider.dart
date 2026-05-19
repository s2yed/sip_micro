import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SipSettings {
  final String myExtension;
  final String callTarget;

  const SipSettings({required this.myExtension, required this.callTarget});

  bool get isConfigured => myExtension.isNotEmpty && callTarget.isNotEmpty;
}

class SipSettingsNotifier extends AsyncNotifier<SipSettings> {
  static const _keyMy = 'sip_my_ext';
  static const _keyTarget = 'sip_target';

  @override
  Future<SipSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return SipSettings(
      myExtension: prefs.getString(_keyMy) ?? '',
      callTarget: prefs.getString(_keyTarget) ?? '',
    );
  }

  Future<void> save({
    required String myExtension,
    required String callTarget,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMy, myExtension);
    await prefs.setString(_keyTarget, callTarget);
    state = AsyncData(
      SipSettings(myExtension: myExtension, callTarget: callTarget),
    );
  }
}

final sipSettingsProvider =
    AsyncNotifierProvider<SipSettingsNotifier, SipSettings>(
      SipSettingsNotifier.new,
    );
