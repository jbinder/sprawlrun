import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/data/gpx_export.dart';
import 'package:sprawl_run/models/run_record.dart';

import 'support/fakes.dart';

void main() {
  // A winter date, so the local-to-UTC conversion is visible in the output
  // rather than hidden by a zero offset.
  final startedAt = DateTime.utc(2026, 1, 15, 7, 30).toLocal();

  const trace = [
    TracePoint(lat: 48.20849, lon: 16.37208, elapsedSeconds: 0),
    TracePoint(lat: 48.20901, lon: 16.37311, elapsedSeconds: 30.4, speedMps: 3.1),
    TracePoint(lat: 48.20977, lon: 16.37402, elapsedSeconds: 61.8, speedMps: 3.3),
  ];

  group('GPX document', () {
    test('is a well-formed GPX 1.1 track with one point per fix', () {
      final gpx = GpxExport.of(run(at: startedAt, missionId: 'sp01'), trace);

      expect(gpx, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(gpx, contains('<gpx version="1.1" creator="SPRAWL//RUN"'));
      expect(gpx, contains('xmlns="http://www.topografix.com/GPX/1/1"'));
      expect(gpx, contains('<type>running</type>'));
      expect('<trkpt '.allMatches(gpx).length, trace.length);
      expect(gpx.trimRight(), endsWith('</gpx>'));

      // Every tag that opens, closes. `<trk>` is matched with its bracket so
      // it does not also count `<trkseg>` and `<trkpt`.
      for (final tag in ['gpx', 'metadata', 'trk', 'trkseg']) {
        expect(RegExp('<$tag[ >]').allMatches(gpx).length, 1, reason: tag);
        expect('</$tag>'.allMatches(gpx).length, 1, reason: tag);
      }
    });

    test('timestamps are absolute UTC, offset from the start of the run', () {
      final gpx = GpxExport.of(run(at: startedAt), trace);

      expect(gpx, contains('<time>2026-01-15T07:30:00Z</time>'), reason: 'metadata and first point');
      expect(gpx, contains('<time>2026-01-15T07:30:30Z</time>'), reason: '30.4 s rounds to the second');
      expect(gpx, contains('<time>2026-01-15T07:31:02Z</time>'), reason: '61.8 s');
      expect(gpx, isNot(contains('.000Z')), reason: 'milliseconds are noise in a GPS track');
    });

    test('coordinates keep the precision the trace was stored at', () {
      final gpx = GpxExport.of(run(at: startedAt), trace);
      expect(gpx, contains('lat="48.20849" lon="16.37208"'));
    });

    test('elevation is omitted rather than invented', () {
      expect(GpxExport.of(run(at: startedAt), trace), isNot(contains('<ele>')));
    });

    test('a run without a trace is still a valid, empty track', () {
      final gpx = GpxExport.of(run(at: startedAt), const []);
      expect(gpx, contains('<trkseg>'));
      expect(gpx, isNot(contains('<trkpt')));
      expect(gpx.trimRight(), endsWith('</gpx>'));
    });

    test('a codename with XML characters cannot break the document', () {
      // The fixture derives the codename from the mission id.
      final gpx = GpxExport.of(run(at: startedAt, missionId: 'ghost & <wire>'), trace);
      expect(gpx, contains('<name>GHOST &amp; &lt;WIRE&gt;</name>'));
      expect(gpx, isNot(contains('<WIRE>')));
    });

    test('a free run is named as one', () {
      expect(GpxExport.of(run(at: startedAt), trace), contains('<name>Free run</name>'));
    });
  });

  group('file name', () {
    test('carries the date and the mission, and sorts chronologically', () {
      expect(
        GpxExport.fileName(run(at: DateTime(2026, 9, 23, 6, 41), missionId: 'sp01')),
        'sprawlrun-2026-09-23-0641-sp01.gpx',
      );
      final earlier = GpxExport.fileName(run(at: DateTime(2026, 9, 5, 18, 3)));
      final later = GpxExport.fileName(run(at: DateTime(2026, 9, 23, 6, 41)));
      expect([later, earlier]..sort(), [earlier, later]);
    });

    test('a free run and an awkward codename both give a usable name', () {
      expect(GpxExport.fileName(run(at: DateTime(2026, 9, 23, 6, 41))), 'sprawlrun-2026-09-23-0641-free-run.gpx');
      final odd = run(at: DateTime(2026, 9, 23, 6, 41), missionId: 'ghost & <wire>!');
      expect(GpxExport.fileName(odd), 'sprawlrun-2026-09-23-0641-ghost-wire.gpx');
    });
  });
}
