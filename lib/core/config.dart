import 'package:flutter_dotenv/flutter_dotenv.dart';

class UcmConfig {
  static String get host => dotenv.env['UCM_HOST'] ?? '192.1.1.2';
  static int get wssPort =>
      int.tryParse(dotenv.env['UCM_WSS_PORT'] ?? '') ?? 8089;
  static int get wsPort =>
      int.tryParse(dotenv.env['UCM_WS_PORT'] ?? '') ?? 5000;
  static String get wssPath => dotenv.env['UCM_WSS_PATH'] ?? '/ws';
  static String get sipPassword => dotenv.env['SIP_PASSWORD'] ?? 'qwer369';

  static String get clientMode => dotenv.env['CLIENT_MODE'] ?? 'register'; // 'register', 'anonymous', or 'pool'
  static String get defaultCallTarget => dotenv.env['DEFAULT_CALL_TARGET'] ?? '100';
  static String get anonymousDisplayName => dotenv.env['ANONYMOUS_DISPLAY_NAME'] ?? 'عميل';

  static String get wsUrl => 'wss://$host:$wssPort$wssPath';

  static String? _selectedExtension;

  static String get myExtension {
    if (_selectedExtension != null) return _selectedExtension!;
    final poolStr = dotenv.env['CLIENT_EXTENSIONS_POOL'] ?? dotenv.env['DEFAULT_MY_EXTENSION'] ?? '1034';
    final List<String> list = poolStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (list.isEmpty) {
      _selectedExtension = '1034';
    } else {
      _selectedExtension = (list..shuffle()).first;
    }
    return _selectedExtension!;
  }

  static String sipUri(String ext) => 'sip:$ext@$host';
  static String callUri(String target) => 'sip:$target@$host';
}
