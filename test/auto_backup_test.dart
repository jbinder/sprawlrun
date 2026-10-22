import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/backup.dart';
import 'package:sprawl_run/data/mission_repository.dart';
import 'package:sprawl_run/data/profile_repository.dart';
import 'package:sprawl_run/data/run_repository.dart';
import 'package:sprawl_run/services/backup_folder.dart';
import 'package:sprawl_run/state/app_state.dart';

import 'support/fakes.dart';

/// Automatic backups: off until the runner chooses a folder, then one after
/// every run. A failure is shown rather than thrown, and only a backup that was
/// actually written quiets the nudge.
void main() {
  late Directory root;
  late _Folder folder;
  late AppState state;

  setUp(() async {
    root = tempRoot('auto_backup');
    folder = _Folder();
    state = AppState(
      profiles: ProfileRepository(root),
      runs: RunRepository(Directory('${root.path}/runs')),
      missions: MissionRepository(externalDir: Directory('${root.path}/packs'), bundle: _DiskBundle()),
      narrator: FakeNarrator(),
      backupFolder: folder.asBackupFolder(),
    );
    await state.load();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> finishRun(DateTime at) async {
    await state.completeRun(run(at: at));
    await state.autoBackup();
  }

  test('off until a folder is chosen: a run writes nothing', () async {
    expect(state.autoBackupFolder, isNull);
    await finishRun(DateTime(2026, 10, 1, 7));
    expect(folder.written, isEmpty);
    expect(state.profile.lastExportAt, isNull);
  });

  test('choosing a folder writes the first backup at once', () async {
    await finishRun(DateTime(2026, 10, 1, 7));
    folder.next = 'Sync';
    expect(await state.chooseAutoBackupFolder(), isTrue);

    expect(state.autoBackupFolder, 'Sync');
    expect(folder.written, hasLength(1));
    final (name, json, prefix, keep) = folder.written.single;
    expect(name, startsWith(BackupService.autoPrefix));
    expect((prefix, keep), (BackupService.autoPrefix, AppState.autoBackupsKept));
    expect(BackupArchive.parse(json).runs, hasLength(1), reason: 'the whole device, as a manual export');
    expect(state.profile.lastExportAt, isNotNull, reason: 'a written backup quiets the nudge');
  });

  test('backing out of the picker leaves things as they were', () async {
    expect(await state.chooseAutoBackupFolder(), isFalse);
    expect(state.autoBackupFolder, isNull);
    expect(folder.written, isEmpty);
  });

  test('every recorded run is followed by a backup that includes it', () async {
    folder.next = 'Sync';
    await state.chooseAutoBackupFolder();
    await finishRun(DateTime(2026, 10, 1, 7));
    await finishRun(DateTime(2026, 10, 3, 7));
    expect(folder.written, hasLength(3));
    expect(BackupArchive.parse(folder.written.last.$2).runs, hasLength(2));
  });

  test('a failed write is shown, does not count as an export, and clears on the next success', () async {
    folder.next = 'Sync';
    folder.failWith = 'folder is gone';
    await state.chooseAutoBackupFolder();
    expect(state.autoBackupError, 'folder is gone');
    expect(state.profile.lastExportAt, isNull);

    folder.failWith = null;
    await finishRun(DateTime(2026, 10, 1, 7));
    expect(state.autoBackupError, isNull);
    expect(state.profile.lastExportAt, isNotNull);
  });

  test('turning it off lets go of the folder and stops writing', () async {
    folder.next = 'Sync';
    await state.chooseAutoBackupFolder();
    await state.stopAutoBackup();
    expect(folder.forgotten, isTrue);
    expect(state.autoBackupFolder, isNull);

    await finishRun(DateTime(2026, 10, 1, 7));
    expect(folder.written, hasLength(1), reason: 'only the one written when it was chosen');
  });

  test('automatic backups are named apart from manual ones and sort by time', () {
    final early = BackupService.autoFileName(DateTime(2026, 10, 1, 7, 5, 9));
    final late = BackupService.autoFileName(DateTime(2026, 10, 1, 7, 5, 31));
    expect(early, 'sprawlrun-autobackup-2026-10-01-070509.json');
    expect(early.compareTo(late), lessThan(0), reason: 'two runs in one minute do not collide');
    expect(BackupService.suggestedFileName(DateTime(2026, 10, 1, 7, 5)), isNot(startsWith(BackupService.autoPrefix)));
  });
}

/// A folder the runner might pick, recording what was written to it.
class _Folder {
  String? chosen;
  String? next;
  String? failWith;
  bool forgotten = false;
  final written = <(String, String, String, int)>[];

  BackupFolder asBackupFolder() => BackupFolder(
    current: () async => chosen,
    choose: () async => chosen = next ?? chosen,
    forget: () async {
      forgotten = true;
      chosen = null;
    },
    write: (name, json, {required prefix, required keep}) async {
      if (failWith case final message?) throw BackupFolderException(message);
      written.add((name, json, prefix, keep));
    },
  );
}

class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.view(File(key).readAsBytesSync().buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => File(key).readAsStringSync();
}
