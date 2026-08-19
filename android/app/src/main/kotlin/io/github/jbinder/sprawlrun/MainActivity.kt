package io.github.jbinder.sprawlrun

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Two platform additions the plugins do not cover: repairing a failed audio
 * focus handoff, and making the mission notification actually visible.
 *
 * Android's transient audio focus is a loan: the music app pauses when we take
 * it and is supposed to resume when we give it back. Several popular players
 * only honour that for short interruptions and stay silent after a long one.
 * There is no way to fix that from inside our own focus request, so the app
 * detects the failure and presses PLAY on the runner's behalf.
 *
 * Neither audio call needs a permission, and neither can reach the network.
 */
class MainActivity : FlutterActivity() {
    private val audioChannelName = "io.github.jbinder.sprawlrun/audio"
    private val notificationChannelName = "io.github.jbinder.sprawlrun/notifications"

    /**
     * Hard-coded in geolocator's GeolocatorLocationService. Matching it is the
     * whole point — see [ensureMissionChannel].
     */
    private val missionChannelId = "geolocator_channel_01"

    private val notificationRequestCode = 4711

    private var pendingNotificationResult: MethodChannel.Result? = null

    private val audio: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ensureMissionChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // True when anything is playing on the music stream, ours
                    // included — the caller only asks while we are silent.
                    "isMusicActive" -> result.success(audio.isMusicActive)

                    // Routed to whichever player last held the media session.
                    // KEYCODE_MEDIA_PLAY rather than PLAY_PAUSE: it is
                    // idempotent, so a player that did resume on its own is
                    // never toggled back off by a nudge that raced it.
                    "resumeMusic" -> {
                        audio.dispatchMediaKeyEvent(
                            KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY)
                        )
                        audio.dispatchMediaKeyEvent(
                            KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY)
                        )
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)

                    // Every run, GPS or not — see MissionService.
                    "startMissionNotice" -> {
                        MissionService.start(
                            this,
                            call.argument<String>("text") ?: "",
                            call.argument<Boolean>("tracking") ?: false
                        )
                        result.success(null)
                    }

                    // Same call: the service updates in place once started.
                    "updateMissionNotice" -> {
                        MissionService.start(
                            this,
                            call.argument<String>("text") ?: "",
                            call.argument<Boolean>("tracking") ?: false
                        )
                        result.success(null)
                    }

                    "stopMissionNotice" -> {
                        MissionService.stop(this)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Creates the foreground-service notification channel before geolocator can.
     *
     * geolocator builds the same channel at IMPORTANCE_NONE, which Android
     * treats as blocked: the ongoing notification never reaches the shade and
     * the app is folded into the grouped "running in the background" notice
     * instead. Importance cannot be lowered by a later createNotificationChannel
     * call, so creating it first at IMPORTANCE_LOW wins — geolocator's call then
     * only updates the channel's name.
     *
     * IMPORTANCE_LOW, not DEFAULT: visible and persistent, but silent. A
     * notification that beeps at the start of every run would be worse than the
     * bug.
     *
     * This does not help a device where the channel already exists at
     * IMPORTANCE_NONE — Android keeps the user-visible settings of a channel it
     * has seen, including across delete and recreate, so an existing install has
     * to be fixed from system settings or by reinstalling.
     */
    private fun ensureMissionChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            missionChannelId,
            "Active mission",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.description = "Shown while a mission is tracking your route."
        channel.setShowBadge(false)
        channel.enableVibration(false)
        manager.createNotificationChannel(channel)
    }

    /**
     * Android 13 made POST_NOTIFICATIONS a runtime permission, and without it
     * the foreground service still runs but its notification is suppressed. No
     * plugin here asks for it, so the app has to.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        // A second request while one is in flight would strand the first
        // result, and MethodChannel.Result must be answered exactly once.
        if (pendingNotificationResult != null) {
            result.success(false)
            return
        }
        pendingNotificationResult = result
        requestPermissions(arrayOf(permission), notificationRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationRequestCode) return
        val pending = pendingNotificationResult ?: return
        pendingNotificationResult = null
        pending.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        )
    }
}
