import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/achievements_screen.dart';
import 'screens/codex_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/timeline_screen.dart';
import 'state/app_state.dart';
import 'theme/cyber_palette.dart';
import 'theme/cyber_theme.dart';
import 'theme/season.dart';
import 'widgets/backdrop.dart';
import 'widgets/edge_fade.dart';
import 'widgets/glitch_text.dart';
import 'widgets/signal_watcher.dart';
import 'l10n/l10n.dart';

class SprawlRunApp extends StatelessWidget {
  const SprawlRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A season changes every colour, and colours are read at build time — so
    // when it changes, everything beneath is rebuilt rather than just whatever
    // happens to depend on this.
    final season = context.select<AppState, Season?>((s) => s.season);
    final locale = context.select<AppState, Locale>((s) => s.locale);
    if (Season.apply(season)) {
      SystemChrome.setSystemUIOverlayStyle(cyberOverlayStyle);
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    }
    return MaterialApp(
      title: 'SPRAWL//RUN',
      debugShowCheckedModeBanner: false,
      theme: buildCyberTheme(),
      // Fades a list's edge while there is more beyond it; see edge_fade.dart.
      scrollBehavior: const CyberScrollBehavior(),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      // Resolved by AppState rather than left to MaterialApp, because the
      // notifications it plans have to be written in the same language.
      locale: locale,
      // Beneath the localisations, so code without a context — notification
      // text, the narrator's readouts — speaks the language on screen.
      builder: (context, child) {
        useLocale(Localizations.localeOf(context));
        return child!;
      },
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final loading = context.select<AppState, bool>((s) => s.loading);
    // The watcher only mounts once loading is done, so a tapped signal never
    // lands over the boot screen. Nothing is lost by waiting: the tap stream
    // buffers until something subscribes.
    return loading ? const _BootScreen() : const SignalWatcher(child: HomeShell());
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
              Text(L.of(context).bootEstablishing, style: CyType.label(color: Cy.cyanDim)),
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  // The dot on THE WIRE's icon has to appear while the app sits open, but a
  // signal fires without running any Dart. So the shell looks again when the
  // next one is due, and whenever the app comes back to the foreground.
  late final AppLifecycleListener _lifecycle;
  Timer? _signalTimer;
  DateTime? _signalTimerFor;

  void _checkSignals() => context.read<AppState>().refreshUnreadSignals();

  void _armSignalTimer(DateTime? at) {
    if (at == _signalTimerFor) return;
    _signalTimerFor = at;
    _signalTimer?.cancel();
    _signalTimer = null;
    if (at == null) return;
    // A second late, so the signal is unambiguously in the past by then.
    final wait = at.difference(DateTime.now()) + const Duration(seconds: 1);
    _signalTimer = Timer(wait.isNegative ? Duration.zero : wait, _checkSignals);
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkSignals);
    WidgetsBinding.instance.addObserver(this);
  }

  // Android hands the app the new list without restarting it.
  @override
  void didChangeLocales(List<Locale>? locales) => context.read<AppState>().systemLocalesChanged();

  @override
  void dispose() {
    _signalTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  static List<({IconData icon, IconData active, String label})> _destinations(L l) => [
    (icon: Icons.hexagon_outlined, active: Icons.hexagon, label: l.navOps),
    (icon: Icons.query_stats_outlined, active: Icons.query_stats, label: l.navStats),
    (icon: Icons.military_tech_outlined, active: Icons.military_tech, label: l.navWall),
    (icon: Icons.menu_book_outlined, active: Icons.menu_book, label: l.navCodex),
  ];

  @override
  Widget build(BuildContext context) {
    _armSignalTimer(context.select<AppState, DateTime?>((s) => s.nextSignalAt));
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
                onTimeline: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: TimelineScreen.routeName),
                    builder: (_) => const TimelineScreen(),
                  ),
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
      bottomNavigationBar: PumpkinPerch(
        left: 14,
        size: 23,
        child: _NavBar(
          index: _index,
          destinations: _destinations(L.of(context)),
          onSelect: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings, required this.onTimeline});

  final VoidCallback onSettings;
  final VoidCallback onTimeline;

  @override
  Widget build(BuildContext context) {
    final callsign = context.select<AppState, String>((s) => s.profile.callsign);
    // Up here rather than on the dashboard, which is full enough already. Only
    // shown while the handlers are sending anything — with every signal off
    // there is nothing of theirs to read back.
    final signalsOn = context.select<AppState, bool>((s) => s.profile.signals.anyEnabled);
    final unread = context.select<AppState, bool>((s) => s.hasUnreadSignals);
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
          if (signalsOn)
            IconButton(
              onPressed: onTimeline,
              // A dot, not a count: it says something came in, not how much.
              icon: Badge(
                isLabelVisible: unread,
                smallSize: 8,
                backgroundColor: Cy.magenta,
                child: Icon(Icons.forum_outlined, color: Cy.inkDim),
              ),
              tooltip: unread ? L.of(context).wireTooltipUnread : L.of(context).wireTooltip,
            ),
          IconButton(
            onPressed: onSettings,
            icon: Icon(Icons.settings_outlined, color: Cy.inkDim),
            tooltip: L.of(context).settingsTooltip,
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
      decoration: BoxDecoration(
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
