import '../models/run_record.dart';

/// Writes a run's GPS trace as GPX 1.1 — the format every map app reads,
/// OsmAnd included.
///
/// Pure, like the rest of the derived data: a [RunRecord] plus its trace in,
/// a string out, so the whole format is testable without a device.
abstract final class GpxExport {
  /// Points carry absolute timestamps, which the trace does not store — it
  /// keeps seconds since the run began, so they are added back onto
  /// [RunRecord.startedAt] here.
  ///
  /// Elevation is deliberately absent rather than zero: the app never records
  /// it, and a track claiming sea level everywhere would make an elevation
  /// profile that is a straight lie.
  static String of(RunRecord run, List<TracePoint> trace) {
    final name = run.missionCodename ?? 'Free run';
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="SPRAWL//RUN" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 '
        'http://www.topografix.com/GPX/1/1/gpx.xsd">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_xml(name)}</name>')
      ..writeln('    <time>${_stamp(run.startedAt)}</time>')
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_xml(name)}</name>')
      // OsmAnd and Strava both read this to pick the activity icon.
      ..writeln('    <type>running</type>')
      ..writeln('    <trkseg>');

    for (final p in trace) {
      // Whole seconds: the trace is stored rounded to the second, so finer
      // timestamps here would be made up.
      final at = run.startedAt.add(Duration(seconds: p.elapsedSeconds.round()));
      buf
        ..writeln('      <trkpt lat="${_coord(p.lat)}" lon="${_coord(p.lon)}">')
        ..writeln('        <time>${_stamp(at)}</time>')
        ..writeln('      </trkpt>');
    }

    buf
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buf.toString();
  }

  /// `sprawlrun-2026-09-23-0641-kuang-eleven.gpx` — sorts chronologically and
  /// survives a share sheet on every Android version.
  static String fileName(RunRecord run) {
    String two(int v) => v.toString().padLeft(2, '0');
    final d = run.startedAt;
    final stamp = '${d.year}-${two(d.month)}-${two(d.day)}-${two(d.hour)}${two(d.minute)}';
    final slug = (run.missionCodename ?? 'free-run')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'sprawlrun-$stamp${slug.isEmpty ? '' : '-$slug'}.gpx';
  }

  /// Five decimals is about a metre — the precision the trace is stored at, so
  /// writing more would invent accuracy that was never recorded.
  static String _coord(double v) => v.toStringAsFixed(5);

  static String _stamp(DateTime at) => at.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
