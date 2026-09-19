package io.github.jbinder.sprawlrun

import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Position fixes straight from the GPS provider, as an event stream.
 *
 * geolocator's LocationManager client is not used for the stream because on
 * Android 12+ it silently prefers the "fused" provider whenever the ROM offers
 * one. On a de-Googled device that provider is whatever the vendor shipped, and
 * on at least one Xperia it registers requests happily and never delivers a
 * fix — the run sees a healthy, open, empty stream. Asking the GPS provider by
 * name is what the app has always meant by "AOSP's LocationManager".
 *
 * The request is tied to the Dart subscription: it starts on listen and is
 * removed on cancel. Fixes keep arriving with the screen off because
 * MissionService holds the process in the foreground with the `location` type.
 */
class GpsStream(private val context: Context) : EventChannel.StreamHandler {
    private val manager: LocationManager
        get() = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private var listener: LocationListener? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null)
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            events.error("gpsDisabled", "The GPS provider is switched off.", null)
            return
        }
        val l = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                events.success(
                    mapOf(
                        "lat" to location.latitude,
                        "lon" to location.longitude,
                        "time" to location.time,
                        "accuracy" to if (location.hasAccuracy()) location.accuracy.toDouble() else 1e6,
                        "speed" to if (location.hasSpeed()) location.speed.toDouble() else 0.0,
                        "speedAccuracy" to
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy())
                                location.speedAccuracyMetersPerSecond.toDouble()
                            else 0.0,
                    )
                )
            }

            override fun onProviderDisabled(provider: String) {
                events.error("gpsDisabled", "The GPS provider was switched off.", null)
            }

            override fun onProviderEnabled(provider: String) {}

            // Removed in API 29 but abstract below it; minSdk is 24.
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        try {
            manager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                1000L,
                0f,
                l,
                Looper.getMainLooper()
            )
            listener = l
        } catch (e: SecurityException) {
            events.error("denied", "Location permission is missing.", null)
        }
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.removeUpdates(it) }
        listener = null
    }
}
