import 'package:flutter/material.dart';

import 'services/kb_service.dart';
import 'services/prompt_asset_loader.dart';
import 'services/provider_service.dart';
import 'services/settings_service.dart';
import 'pages/graph_page.dart';
import 'pages/records_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializePromptAssetLoader();
  final settings = await SettingsService.load();
  final providerService = ProviderService(settings);
  final kbService = KbService(settings, providerService);

  runApp(DemoApp(kbService: kbService));
}

class DemoApp extends StatelessWidget {
  final KbService kbService;

  const DemoApp({super.key, required this.kbService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_agent_memory demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(kbService: kbService),
    );
  }
}

class HomePage extends StatefulWidget {
  final KbService kbService;

  const HomePage({super.key, required this.kbService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      RecordsPage(kbService: widget.kbService),
      SearchPage(kbService: widget.kbService),
      GraphPage(kbService: widget.kbService),
      SettingsPage(kbService: widget.kbService),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('flutter_agent_memory demo'),
        actions: [
          ListenableBuilder(
            listenable: widget.kbService,
            builder: (context, _) {
              final configured = widget.kbService.providerService.provider != null;
              return Icon(
                Icons.circle,
                color: configured ? Colors.green : Colors.orange,
                size: 12,
              );
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_books), label: 'Records'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'Graph'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
