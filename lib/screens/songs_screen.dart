import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/song.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/cyber_palette.dart';
import '../util/picked_text.dart';
import '../widgets/library_list.dart';
import '../widgets/panels.dart';
import 'song_library_screen.dart';

/// SONGS on the RIG screen: every song the phone can play, shipped and
/// imported, to share and remove. What a run plays is chosen in Settings →
/// Audio, through the song library there.
class SongsScreen extends StatefulWidget {
  const SongsScreen({super.key});

  @override
  State<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends State<SongsScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final imported = state.songRepository.importedIds;
    final l = L.of(context);
    return LibraryScreen(
      title: l.rigSongs,
      where: l.rigSongsWhere,
      items: [
        for (final song in state.songs)
          if (song.nameIn(state.locale.languageCode) case final name)
            LibraryItem(
              leading: Icon(Icons.graphic_eq, size: 22, color: Cy.magenta),
              title: name,
              lines: [if (song.author == null) songLength(song) else '${l.songBy(song.author!)} · ${songLength(song)}'],
              tag: imported.contains(song.id) ? l.packImported : null,
              tagColor: Cy.green,
              onExport: _busy ? null : () => _export(state, song, name),
              exportTooltip: l.songExportTooltip(name),
              onRemove: imported.contains(song.id) && !_busy ? () => _remove(state, song, name) : null,
              removeTooltip: l.songRemoveTooltip(name),
            ),
      ],
      note: l.songExplainer,
      actions: [
        CyberButton(
          label: _busy ? l.working : l.songImport,
          icon: Icons.library_music_outlined,
          style: CyberButtonStyle.ghost,
          dense: true,
          onPressed: _busy ? null : () => _import(state),
        ),
      ],
    );
  }

  /// Hands the song's file to the share sheet as it is stored: a shipped one
  /// too, as a start for writing one's own.
  Future<void> _export(AppState state, Song song, String name) async {
    final source = await state.songRepository.sourceOf(song.id);
    if (source == null || !mounted) return;
    await shareJson(context, name: song.id, source: source, subject: l10n.songShareSubject(name));
  }

  Future<void> _remove(AppState state, Song song, String name) async {
    setState(() => _busy = true);
    try {
      await state.removeSong(song.id);
      if (mounted) sayOnLibrary(context, l10n.songRemoved(name));
    } on Object catch (e) {
      if (mounted) sayOnLibrary(context, l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Brings in a song file written in the app's own format (docs/SONGS.md),
  /// through the system file picker, as themes and packs come in.
  Future<void> _import(AppState state) async {
    setState(() => _busy = true);
    try {
      // Permissive, as for packs: some document providers do not tag .json.
      final picked = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(label: l10n.songFileType, extensions: ['json'], mimeTypes: ['application/json']),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > Song.maxBytes) throw const SongFormatException('The file is too large for a song');
      final song = await state.importSong(await readPickedText(picked));
      if (mounted) sayOnLibrary(context, l10n.songImported(song.nameIn(state.locale.languageCode)));
    } on SongFormatException catch (e) {
      if (mounted) sayOnLibrary(context, e.message, bad: true);
    } on Object catch (e) {
      if (mounted) sayOnLibrary(context, l10n.importFailed('$e'), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
