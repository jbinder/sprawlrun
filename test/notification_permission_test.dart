import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprawl_run/services/notification_permission.dart';

/// The platform side of this is a request dialog, which no test can drive. What
/// is worth pinning down is the contract around it: the app must never treat an
/// unanswerable channel as a grant, and must never leave a run un-started
/// because notifications were refused.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('io.github.jbinder.sprawlrun/notifications');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('reports the grant the platform gives', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });

    expect(await NotificationPermission.platform().request(), isTrue);
    expect(calls, ['requestPermission']);
  });

  test('a refusal is reported, not swallowed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await NotificationPermission.platform().request(), isFalse);
  });

  test('a null reply counts as refused', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await NotificationPermission.platform().request(), isFalse);
  });

  test('a platform failure resolves rather than throwing', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'boom'),
    );
    expect(await NotificationPermission.platform().request(), isFalse);
  });

  test('no handler at all resolves rather than hanging the run', () async {
    expect(await NotificationPermission.platform().request(), isFalse);
  });

  test('non-Android platforms have nothing to ask for', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = true;
      return false;
    });

    expect(await NotificationPermission.platform().request(), isTrue);
    expect(asked, isFalse);
  });
}
