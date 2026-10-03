import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/split_readout.dart';

/// The readout is heard, not read, so durations are spelled out in words a
/// speech engine cannot turn into a time of day.
void main() {
  test('durations read the way a person would say them', () {
    expect(SplitReadout.spoken(41), '41 seconds');
    expect(SplitReadout.spoken(1), '1 second');
    expect(SplitReadout.spoken(341), '5 minutes 41');
    expect(SplitReadout.spoken(360), '6 minutes');
    expect(SplitReadout.spoken(65), '1 minute 5');
    expect(SplitReadout.spoken(3725), '1 hour 2 minutes', reason: 'no seconds past the hour');
    expect(SplitReadout.spoken(7200), '2 hours');
  });

  test('no colons for an engine to misread', () {
    final line = SplitReadout.line(count: 3, metric: true, splitSeconds: 341, totalSeconds: 1024);
    expect(line, 'Kilometre 3. Split 5 minutes 41. Total 17 minutes 4.');
    expect(line, isNot(contains(':')));
  });

  test('miles for a runner who uses them', () {
    expect(SplitReadout.line(count: 1, metric: false, splitSeconds: 540, totalSeconds: 540), startsWith('Mile 1.'));
  });
}
