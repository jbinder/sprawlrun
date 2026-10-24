package io.github.jbinder.sprawlrun

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import io.flutter.plugin.common.EventChannel

/**
 * The phone's hardware step counter, as an event stream of its running total.
 *
 * TYPE_STEP_COUNTER is AOSP's own sensor, counted by the sensor hub rather than
 * the app, so it keeps counting with the screen off and needs no Play
 * Services. Its total runs from the last reboot; the run takes the difference
 * from the first value it sees. Reported without batching, so a step reaches
 * the run within a second — moving time is judged from it when GPS is quiet.
 *
 * Like [GpsStream], the listener is tied to the Dart subscription. Reading it
 * needs ACTIVITY_RECOGNITION from Android 10 on, which the runner grants only
 * by turning step counting on in Settings; a run never asks for it.
 */
class StepStream(private val context: Context) : EventChannel.StreamHandler {
    companion object {
        fun sensor(context: Context): Sensor? =
            (context.getSystemService(Context.SENSOR_SERVICE) as SensorManager?)
                ?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)

        fun hasPermission(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                context.checkSelfPermission(android.Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED
    }

    private val manager: SensorManager
        get() = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

    private var listener: SensorEventListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        val counter = sensor(context)
        if (counter == null) {
            events.error("noSensor", "This device has no step counter.", null)
            return
        }
        if (!hasPermission(context)) {
            events.error("denied", "The physical-activity permission is missing.", null)
            return
        }
        val l = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                events.success(event.values[0].toLong())
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        manager.registerListener(l, counter, SensorManager.SENSOR_DELAY_NORMAL, 0)
        listener = l
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.unregisterListener(it) }
        listener = null
    }
}
