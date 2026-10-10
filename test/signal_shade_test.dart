import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/signal_planner.dart';
import 'package:sprawl_run/services/signal_scheduler.dart';

/// Opening the app re-plans its signals, and the re-plan used to cancel every
/// signal id — which also removes one already sitting unread in the shade. A
/// runner who opened the app without tapping the notification lost the message.
void main() {
  PlannedSignal at(int id, {SignalKind kind = SignalKind.reminder}) => PlannedSignal(
    id: id,
    at: DateTime(2026, 10, 12, 18),
    kind: kind,
    from: 'KESTREL',
    text: 'line $id',
    ref: 'r$id',
  );

  group('cancelling', () {
    test('only signals still waiting are cancelled — never one already shown', () {
      // 7003 fired and sits in the shade, so the plugin no longer lists it as
      // pending; 7004 and 7101 are still waiting.
      expect(SignalScheduler.cancellable([7004, 7101]), [7004, 7101]);
    });

    test('nothing outside the signal ids, such as the run notice', () {
      expect(SignalScheduler.cancellable([75416, 6999, 7000, 7299, 7300]), [7000, 7299]);
    });
  });

  group('a new plan steers clear of what is on screen', () {
    test('a signal whose id is still shown moves to a free id in its own band', () {
      final plan = SignalScheduler.sparingShown([at(7003), at(7004)], {7003});
      expect(plan.map((s) => s.id), isNot(contains(7003)), reason: 'or it would replace the unread one when it fires');
      expect(plan.first.id, inInclusiveRange(7000, 7099), reason: 'still a reminder id');
      expect(plan.map((s) => s.id).toSet(), hasLength(2), reason: 'no two signals share an id');
      expect(plan.first.text, 'line 7003', reason: 'only the id changes');
    });

    test('noise and debriefs stay in their own bands', () {
      final plan = SignalScheduler.sparingShown(
        [at(7100, kind: SignalKind.ambient), at(7200, kind: SignalKind.debrief)],
        {7100, 7200},
      );
      expect(plan[0].id, inInclusiveRange(7101, 7199));
      expect(plan[1].id, inInclusiveRange(7201, 7299));
    });

    test('nothing shown, nothing moved', () {
      final plan = [at(7000), at(7100)];
      expect(SignalScheduler.sparingShown(plan, const {}), same(plan));
    });

    test('a full band keeps the signal rather than dropping it', () {
      final shown = {for (var id = 7000; id < 7100; id++) id};
      expect(SignalScheduler.sparingShown([at(7005)], shown).single.id, 7005);
    });
  });
}
