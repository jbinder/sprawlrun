import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/models/profile.dart';
import 'package:sprawl_run/screens/run_screen.dart';

/// The free-run panel once promised "nothing will interrupt your audio" while
/// the splits readout was talking over the runner's music every kilometre.
void main() {
  test('with splits on, the note says what will speak', () {
    expect(freeRunAudioNote(const Profile()), contains('kilometre'));
    expect(freeRunAudioNote(const Profile()), isNot(contains('nothing')));
    expect(freeRunAudioNote(const Profile(units: UnitSystem.imperial)), contains('mile'));
  });

  test('with splits off, silence is promised', () {
    expect(freeRunAudioNote(const Profile(splitsEnabled: false)), 'Free run — nothing will interrupt your audio.');
  });
}
