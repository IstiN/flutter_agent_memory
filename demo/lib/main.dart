import 'package:flutter/material.dart';

import 'services/kb_service.dart';
import 'services/prompt_asset_loader.dart';
import 'services/provider_service.dart';
import 'services/settings_service.dart';
import 'pages/graph_page.dart';
import 'pages/records_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';

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
      themeMode: ThemeMode.dark,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
              ),
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppColors.primaryGlow, AppColors.secondaryGlow],
              ).createShader(bounds),
              child: const Text(
                'flutter_agent_memory',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Text(
              ' demo',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: widget.kbService,
            builder: (context, _) {
              final configured = widget.kbService.providerService.provider != null;
              return Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: configured
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: configured
                        ? AppColors.success.withValues(alpha: 0.4)
                        : AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      configured ? Icons.bolt : Icons.bolt_outlined,
                      size: 14,
                      color: configured ? AppColors.success : AppColors.warning,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      configured ? 'LLM ready' : 'LLM off',
                      style: TextStyle(
                        color: configured ? AppColors.success : AppColors.warning,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppColors.surface.withValues(alpha: 0.95),
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree),
            label: 'Graph',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
