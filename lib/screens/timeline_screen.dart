import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mission.dart';
import '../models/profile.dart';
import '../models/signal_log.dart';
import '../services/timeline.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../util/format.dart';
import '../widgets/backdrop.dart';
import '../widgets/filter_rail.dart';
import '../widgets/panels.dart';
import 'run_detail_screen.dart';

/// THE WIRE — everything that has come over it, newest first: the handlers'
/// messages, runs, cleared operations, achievements and intel. Called the
/// timeline in code, which is what it is to a programmer; the runner sees the
/// in-world name, alongside OPS, WALL and CODEX.
///
/// Read-only scrollback, not an inbox — nothing is unread, nothing needs
/// clearing. It exists because a signal swiped from the shade was otherwise
/// gone for good, and because only here can a runner see the shape of a week.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, this.focus});

  /// A signal the runner just tapped in the shade, to scroll to and mark.
  final Signal? focus;

  /// Route name, so a second tap replaces an open timeline rather than
  /// stacking another on top of it.
  static const String routeName = '/timeline';

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

/// What the rail can narrow THE WIRE down to. At two signals a day the
/// messages outnumber everything else several times over, so a runner looking
/// for a run or an unlock needs a way past them.
enum _WireFilter {
  all('ALL', null),
  messages('MESSAGES', Icons.forum_outlined),
  runs('RUNS', Icons.directions_run),
  unlocks('UNLOCKS', Icons.military_tech_outlined);

  const _WireFilter(this.label, this.icon);
  final String label;
  final IconData? icon;

  bool admits(TimelineEntry e) => switch (this) {
    all => true,
    messages => e.kind == TimelineKind.signal,
    runs => e.kind == TimelineKind.run,
    unlocks => e.kind == TimelineKind.achievement || e.kind == TimelineKind.codex,
  };
}

class _TimelineScreenState extends State<TimelineScreen> {
  final GlobalKey _focusKey = GlobalKey();
  bool _scrolled = false;
  _WireFilter _filter = _WireFilter.all;

  @override
  void initState() {
    super.initState();
    // The archive is read here rather than at launch: it is the only screen
    // that needs years of it. Runs and unlocks show at once; messages join a
    // moment later, the first time per launch.
    context.read<AppState>().loadSignalArchive();
  }

  /// The projection, kept until one of its inputs changes. Building it is
  /// cheap — about two milliseconds over ten years of daily runs — but this
  /// screen rebuilds on every filter tap and every AppState notification, and
  /// there is no reason to pay for it each time.
  List<TimelineEntry>? _built;
  Object? _builtFrom;

  List<TimelineEntry> _project(AppState state) {
    // Records compare field by field, and the lists and profile compare by
    // identity — which is exactly "has AppState replaced any of these".
    final from = (state.signalHistory, state.runLog, state.profile, state.packs);
    if (_built == null || from != _builtFrom) {
      _builtFrom = from;
      _built = Timeline.build(
        signals: state.signalHistory,
        runs: state.runLog,
        profile: state.profile,
        packs: state.packs,
      );
    }
    return _built!;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    var entries = _project(state);

    // The newest matching signal is the one just tapped; repeats of a line are
    // weeks apart. Should it be missing — scheduled by a build from before the
    // archive existed — it is shown at the top rather than not at all. Held as
    // the entry itself rather than an index, so it survives filtering.
    final focus = widget.focus;
    TimelineEntry? focused;
    if (focus != null) {
      focused = entries
          .where((e) => e.kind == TimelineKind.signal && e.title == focus.from && e.body == focus.text)
          .firstOrNull;
      if (focused == null) {
        focused = TimelineEntry(at: DateTime.now(), kind: TimelineKind.signal, title: focus.from, body: focus.text);
        entries = [focused, ...entries];
      }
    }

    final total = entries.length;
    entries = entries.where(_filter.admits).toList();
    final rows = _rows(entries);
    final focusRow = focused == null ? -1 : rows.indexWhere((r) => identical(r, focused));

    // Not until the archive is in: before that, a tapped signal is shown as a
    // placeholder at the top, and the real entry it is replaced by is the one
    // to scroll to.
    if (focusRow >= 0 && !_scrolled && state.signalArchiveReady) {
      _scrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _focusKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target, alignment: 0.15, duration: const Duration(milliseconds: 300));
        }
      });
    }

    return Scaffold(
      body: GridBackdrop(
        accent: Cy.magenta,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Cy.inkDim),
                    ),
                    const Spacer(),
                    Text('THE WIRE · $total', style: CyType.label(size: 10)),
                  ],
                ),
              ),
              FilterRail(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                children: [
                  for (final f in _WireFilter.values) ...[
                    if (f != _WireFilter.values.first) const SizedBox(width: 8),
                    RailChip(
                      label: f.label,
                      icon: f.icon,
                      selected: _filter == f,
                      onTap: () => setState(() => _filter = f),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: entries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: total == 0
                            ? const EmptyState(
                                title: 'Nothing yet',
                                body: 'Runs, messages from your handler and everything you unlock will appear here.',
                                icon: Icons.timeline,
                              )
                            : const EmptyState(
                                title: 'Nothing of that kind',
                                body: 'Nothing on the wire matches this filter yet.',
                                icon: Icons.filter_alt_off_outlined,
                              ),
                      )
                    // Lazy: a long history is thousands of rows, and only the
                    // top of it is ever looked at.
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          if (row is DateTime) return _DayHeader(day: row);
                          final entry = row as TimelineEntry;
                          return _EntryRow(
                            key: i == focusRow ? _focusKey : null,
                            entry: entry,
                            focused: i == focusRow,
                            units: state.profile.units,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Entries with a day header in front of each new day.
  static List<Object> _rows(List<TimelineEntry> entries) {
    final rows = <Object>[];
    DateTime? day;
    for (final e in entries) {
      final d = DateTime(e.at.year, e.at.month, e.at.day);
      if (d != day) {
        rows.add(d);
        day = d;
      }
      rows.add(e);
    }
    return rows;
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = switch (today.difference(day).inDays) {
      0 => 'TODAY',
      1 => 'YESTERDAY',
      _ => '${Fmt.weekday(day).toUpperCase()} · ${Fmt.date(day).toUpperCase()}',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SectionHeader(label, accent: Cy.magenta),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({super.key, required this.entry, required this.focused, required this.units});

  final TimelineEntry entry;
  final bool focused;
  final UnitSystem units;

  (IconData, Color, String) get _look => switch (entry.kind) {
    TimelineKind.signal => switch (entry.signalKind) {
      SignalKind.ambient => (Icons.wifi_tethering, Cy.magenta, 'SIGNAL NOISE'),
      SignalKind.debrief => (Icons.assignment_outlined, Cy.magenta, 'WEEKLY DEBRIEF'),
      _ => (Icons.forum_outlined, Cy.magenta, 'MESSAGE'),
    },
    TimelineKind.run => (Icons.directions_run, entry.cleared ? Cy.green : Cy.cyan, 'RUN'),
    TimelineKind.achievement => (Icons.military_tech_outlined, Cy.amber, 'ACHIEVEMENT'),
    TimelineKind.codex => (Icons.menu_book_outlined, Cy.cyanDim, 'CODEX'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = _look;
    final time = '${entry.at.hour.toString().padLeft(2, '0')}:${entry.at.minute.toString().padLeft(2, '0')}';
    final run = entry.run;
    final body = run == null
        ? entry.body
        : '${Fmt.distanceWithUnit(run.distanceMeters, units)} · ${Fmt.clock(run.elapsedSeconds)}';

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(entry.title, style: CyType.label(size: 11, color: color))),
                  Text('$label · $time', style: CyType.mono(size: 10, color: Cy.ghost)),
                ],
              ),
              if (body != null) ...[
                const SizedBox(height: 4),
                Text(body, style: CyType.body(size: 14, color: Cy.ink, height: 1.45)),
              ],
            ],
          ),
        ),
      ],
    );

    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: focused ? NeonPanel(accent: Cy.magenta, lit: true, child: content) : content,
    );

    if (run == null) return tile;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunDetailScreen(run: run))),
      child: tile,
    );
  }
}
