import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Anything that can count steps. The run engine only ever sees this, as it
/// only sees a `LocationSource`, so a test can walk a run without a phone.
abstract class StepSource {
  /// The step counter's running total, which starts wherever it likes — the
  /// run takes differences. An error means no steps will come this run.
  Stream<int> counts();

  Future<void> stop();
}

/// Whether steps can be counted here, and the permission they need. Settings
/// asks; a run never does.
class StepSetup {
  const StepSetup({required this.available, required this.granted, required this.request});

  /// The phone has a step counter.
  final Future<bool> Function() available;

  /// The physical-activity permission is held — always true below Android 10.
  final Future<bool> Function() granted;

  /// Shows Android's permission prompt; true when granted.
  final Future<bool> Function() request;

  /// No step counter at all: tests, and every platform but Android.
  factory StepSetup.none() =>
      StepSetup(available: () async => false, granted: () async => false, request: () async => false);

  factory StepSetup.platform() {
    if (defaultTargetPlatform != TargetPlatform.android) return StepSetup.none();
    const channel = MethodChannel('io.github.jbinder.sprawlrun/step_setup');
    Future<bool> ask(String method) async {
      try {
        return await channel.invokeMethod<bool>(method) ?? false;
      } on PlatformException catch (e) {
        debugPrint('step setup $method failed: $e');
        return false;
      } on MissingPluginException {
        return false;
      }
    }

    return StepSetup(
      available: () => ask('available'),
      granted: () => ask('granted'),
      request: () => ask('requestPermission'),
    );
  }
}

/// The phone's hardware step counter (`StepStream.kt`).
class SensorStepSource implements StepSource {
  static const _steps = EventChannel('io.github.jbinder.sprawlrun/steps');

  StreamSubscription<Object?>? _sub;
  StreamController<int>? _controller;

  @override
  Stream<int> counts() {
    _controller?.close();
    final controller = StreamController<int>.broadcast(onCancel: stop);
    _controller = controller;
    _sub = _steps.receiveBroadcastStream().listen(
      (raw) => controller.add(raw! as int),
      onError: controller.addError,
      cancelOnError: true,
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
  }
}
