import 'package:flutter_dotenv/flutter_dotenv.dart';

class UcmConfig {
  static String get host => dotenv.env['UCM_HOST'] ?? '192.1.1.2';
  static int get wssPort =>
      int.tryParse(dotenv.env['UCM_WSS_PORT'] ?? '') ?? 8089;
  static int get wsPort =>
      int.tryParse(dotenv.env['UCM_WS_PORT'] ?? '') ?? 5000;
  static String get wssPath => dotenv.env['UCM_WSS_PATH'] ?? '/ws';
  static String get sipPassword => dotenv.env['SIP_PASSWORD'] ?? 'qwer369';

  static String get wsUrl => 'wss://$host:$wssPort$wssPath';

  static String sipUri(String ext) => 'sip:$ext@$host';
  static String callUri(String target) => 'sip:$target@$host';
}
