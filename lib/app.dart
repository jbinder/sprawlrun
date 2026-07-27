import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/achievements_screen.dart';
import 'screens/codex_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'state/app_state.dart';
import 'theme/cyber_palette.dart';
import 'theme/cyber_theme.dart';
import 'widgets/backdrop.dart';
import 'widgets/glitch_text.dart';

class SprawlRunApp extends StatelessWidget {
  const SprawlRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPRAWL//RUN',
      debugShowCheckedModeBanner: false,
      theme: buildCyberTheme(),
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final loading = context.select<AppState, bool>((s) => s.loading);
    return loading ? const _BootScreen() : const HomeShell();
  }
}

/// Cold boot sequence. Brief, and it doubles as the loading indicator while
/// the profile, run log and mission packs come off disk.
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GridBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlitchText(
                'SPRAWL//RUN',
                alwaysOn: true,
                style: CyType.display(size: 26, color: Cy.ink, shadows: textGlow(Cy.cyan)),
              ),
              const SizedBox(height: 14),
              Text('ESTABLISHING CHANNEL', style: CyType.label(color: Cy.cyanDim)),
              const SizedBox(height: 22),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Cy.rule,
                  color: Cy.cyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four destinations plus settings. The runner should never be more than one
/// tap from starting the next mission.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.hexagon_outlined, active: Icons.hexagon, label: 'OPS'),
    (icon: Icons.query_stats_outlined, active: Icons.query_stats, label: 'STATS'),
    (icon: Icons.military_tech_outlined, active: Icons.military_tech, label: 'WALL'),
    (icon: Icons.menu_book_outlined, active: Icons.menu_book, label: 'CODEX'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopBar(
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [
                    DashboardScreen(),
                    StatsScreen(),
                    AchievementsScreen(),
                    CodexScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _NavBar(
        index: _index,
        destinations: _destinations,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final callsign = context.select<AppState, String>((s) => s.profile.callsign);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
      child: Row(
        children: [
          Container(width: 3, height: 22, color: Cy.cyan),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GlitchText(
                'SPRAWL//RUN',
                style: CyType.display(size: 15, color: Cy.ink, shadows: textGlow(Cy.cyan, blur: 10)),
              ),
              const SizedBox(height: 2),
              Text(callsign.toUpperCase(), style: CyType.label(size: 9, color: Cy.cyanDim)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, color: Cy.inkDim),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.destinations, required this.onSelect});

  final int index;
  final List<({IconData icon, IconData active, String label})> destinations;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Cy.v0id,
        border: Border(top: BorderSide(color: Cy.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: _NavItem(destination: destinations[i], selected: i == index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected});

  final ({IconData icon, IconData active, String label}) destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Cy.cyan : Cy.ghost;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // A lit rule along the top edge marks the active tab, which reads
        // better against the grid than a filled pill would.
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 2,
          width: selected ? 34 : 0,
          decoration: BoxDecoration(color: Cy.cyan, boxShadow: glow(Cy.cyan, blur: 8, opacity: 0.7)),
        ),
        const SizedBox(height: 8),
        Icon(selected ? destination.active : destination.icon, size: 19, color: color),
        const SizedBox(height: 4),
        Text(destination.label, style: CyType.label(size: 9, color: color)),
      ],
    );
  }
}
