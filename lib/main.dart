import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'features/voip/call_screen.dart';
import 'features/voip/setup_screen.dart';
import 'features/voip/sip_settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: SipApp()));
}

class SipApp extends StatelessWidget {
  const SipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'اتصل',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const _HomeRouter(),
    );
  }
}

class _HomeRouter extends ConsumerWidget {
  const _HomeRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(sipSettingsProvider);
    return settings.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0D1B2A),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, e) => const SetupScreen(),
      data: (s) => s.isConfigured ? const CallScreen() : const SetupScreen(),
    );
  }
}
