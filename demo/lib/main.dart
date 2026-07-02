import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'services/kb_service.dart';
import 'services/prompt_asset_loader.dart';
import 'services/provider_service.dart';
import 'services/settings_service.dart';
import 'pages/dashboard_page.dart';
import 'theme/app_theme.dart';
import 'widgets/mermaid_renderer.dart' show registerMermaidPlatformView;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) registerMermaidPlatformView();
  initializePromptAssetLoader();
  final settings = await SettingsService.load();
  final providerService = ProviderService(settings);
  final kbService = KbService(settings, providerService);

  runApp(DemoApp(kbService: kbService));
}

class DemoApp extends StatefulWidget {
  final KbService kbService;

  const DemoApp({super.key, required this.kbService});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.ensureSemantics();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_agent_memory demo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      home: HomePage(kbService: widget.kbService),
    );
  }
}

class HomePage extends StatelessWidget {
  final KbService kbService;

  const HomePage({super.key, required this.kbService});

  @override
  Widget build(BuildContext context) {
    return DashboardPage(kbService: kbService);
  }
}
