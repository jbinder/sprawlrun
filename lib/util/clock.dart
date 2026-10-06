/// The app's idea of "now", for everything *derived* from the time: which week
/// is this week, how long a streak has left, how long ago something was, what
/// the greeting says.
///
/// Things that *record* a moment — an export's file name, when a nudge was
/// snoozed, the stamp on a quarantined file — read the real clock directly,
/// because they are facts about this device.
///
/// In the app this is the real clock. [debugNow] pins it for
/// `tool/screenshots/capture_test.dart`: left to the real clock, the store
/// screenshots changed with the hour and the weekday they were taken on — on a
/// Monday the sample week was nearly empty and the streak card read "1 MIN to
/// go". Named `debug` in the Flutter sense; nothing in the app sets it.
DateTime appNow() => debugNow ?? DateTime.now();

DateTime? debugNow;
