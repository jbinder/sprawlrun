import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/song.dart';
import '../l10n/l10n.dart';
import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../theme/cyber_theme.dart';
import '../widgets/backdrop.dart';
import '../widgets/panels.dart';

/// The songs the phone can play, and how a run chooses among them.
///
/// A list and not a picker's options, since songs can be added: a dropdown would
/// not survive many of them, and has no room to say whose each one is.
class SongLibraryScreen extends StatelessWidget {
  const SongLibraryScreen({super.key});

  static const String _one = 'one';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.profile;
    final l = L.of(context);
    final songs = state.songs;
    final auto = profile.music == Profile.shuffleMusic || profile.music == Profile.bestMatchMusic;
    final kept = songs.where((s) => !profile.songsLeftOut.contains(s.id)).length;
    return Scaffold(
      body: GridBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back, color: Cy.inkDim),
                  ),
                  Expanded(
                    child: Text(
                      l.musicSongLibrary.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CyType.display(size: 14, color: Cy.ink),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: [
                    NeonPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.musicLibraryNote, style: CyType.body(size: 13, color: Cy.ghost, height: 1.4)),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2, right: 6),
                                child: Icon(Icons.warning_amber_rounded, size: 14, color: Cy.amber),
                              ),
                              Expanded(
                                child: Text(
                                  l.musicBatteryNote,
                                  style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _ModeRow(
                            value: auto ? profile.music : _one,
                            options: {
                              Profile.bestMatchMusic: l.musicBestMatch.toUpperCase(),
                              Profile.shuffleMusic: l.musicShuffle.toUpperCase(),
                              _one: l.musicOneSong.toUpperCase(),
                            },
                            onChanged: (mode) => state.updateProfile(
                              profile.copyWith(music: mode == _one ? _firstSong(profile, songs) : mode),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            auto ? l.musicLeaveOutNote : l.musicOneSongNote,
                            style: CyType.body(size: 13, color: Cy.ghost, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    NeonPanel(
                      child: Column(
                        children: [
                          for (final (i, song) in songs.indexed) ...[
                            if (i > 0) Divider(height: 20, color: Cy.inkDim.withValues(alpha: 0.2)),
                            _SongRow(
                              song: song,
                              name: song.nameIn(state.locale.languageCode),
                              chosen: !auto && profile.music == song.id,
                              kept: auto ? !profile.songsLeftOut.contains(song.id) : null,
                              // The last one stays: all off would be silence nobody asked for.
                              lastKept: kept == 1,
                              onChosen: auto ? null : () => state.updateProfile(profile.copyWith(music: song.id)),
                              onKept: (on) => state.updateProfile(
                                profile.copyWith(
                                  songsLeftOut: on
                                      ? [for (final id in profile.songsLeftOut) if (id != song.id) id]
                                      : [...profile.songsLeftOut, song.id],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What One song starts on: the choice it was last on is gone by then, so the
  /// first song that is in.
  String _firstSong(Profile profile, List<Song> songs) => songs
      .firstWhere((s) => !profile.songsLeftOut.contains(s.id), orElse: () => songs.first)
      .id;
}

/// How the library plays, across the whole width, since these labels have no
/// room to spare beside a label of their own.
class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.value, required this.options, required this.onChanged});

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, entry) in options.entries.indexed)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: InkWell(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.key == value ? Cy.cyan : Colors.transparent,
                  border: Border.all(color: entry.key == value ? Cy.cyan : Cy.inkDim),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    style: CyType.mono(size: 10, color: entry.key == value ? Cy.v0id : Cy.inkDim),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.name,
    required this.chosen,
    required this.kept,
    required this.lastKept,
    required this.onChosen,
    required this.onKept,
  });

  final Song song;
  final String name;
  final bool chosen;

  /// Whether it is in the running, or null where a switch means nothing.
  final bool? kept;
  final bool lastKept;
  final VoidCallback? onChosen;
  final ValueChanged<bool> onKept;

  String get _length {
    final seconds = (song.bars * beatsPerBar * song.secondsPerBeat).round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final by = song.author == null ? _length : '${l.songBy(song.author!)} · $_length';
    return InkWell(
      onTap: onChosen,
      child: Row(
        children: [
          if (kept == null) ...[
            Icon(
              chosen ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 18,
              color: chosen ? Cy.cyan : Cy.inkDim,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: CyType.body(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(by, style: CyType.body(size: 12, color: Cy.ghost, height: 1.3)),
              ],
            ),
          ),
          if (kept case final on?) Switch(value: on, onChanged: on && lastKept ? null : onKept),
        ],
      ),
    );
  }
}
