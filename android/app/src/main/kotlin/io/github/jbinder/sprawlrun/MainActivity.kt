package io.github.jbinder.sprawlrun

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import java.lang.ref.WeakReference
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Three platform additions the plugins do not cover: repairing a failed audio
 * focus handoff, making the mission notification actually visible, and
 * reading the GPS provider directly (see [GpsStream]).
 *
 * Android's transient audio focus is a loan: the music app pauses when we take
 * it and is supposed to resume when we give it back. Several popular players
 * only honour that for short interruptions and stay silent after a long one.
 * There is no way to fix that from inside our own focus request, so the app
 * detects the failure and presses PLAY on the runner's behalf.
 *
 * Neither audio call needs a permission, and neither can reach the network.
 *
 * **The Flutter engine outlives this activity while a run is active.** The
 * run — clock, route, story — lives in Dart, in this engine. By default a
 * FlutterActivity owns its engine and destroys it in onDestroy, so swiping the
 * app away from recents threw away a run in progress, track and all; a runner
 * lost a whole run that way. Now the engine is created once, kept in
 * [FlutterEngineCache], and destroyed with the activity only when
 * [MissionService] is not running. The service keeps the process alive, so
 * the run carries on headless — GPS, ticks, lines, notification — and opening
 * the app again, from the notification or the launcher, attaches to the same
 * engine and lands back on the live run.
 *
 * That is why every channel is installed once per engine, against the
 * application context, in [provideFlutterEngine] — not in
 * configureFlutterEngine, which runs again for every activity that attaches.
 * The run calls these channels with no activity at all (GPS fixes, notice
 * updates, the music nudge), and re-registering GPS's stream handler under a
 * live subscription would orphan its LocationListener. Only the permission
 * request needs an activity, and it uses whichever one is [attached].
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "sprawlrun"

        /** The activity on screen, for the one call that needs an Activity. */
        private var attached: WeakReference<MainActivity>? = null

        // In the companion so the engine-lifetime channel handlers that call
        // it hold no reference to whichever activity happened to create them.
        private fun hasNotificationPermission(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }

    private val audioChannelName = "io.github.jbinder.sprawlrun/audio"
    private val notificationChannelName = "io.github.jbinder.sprawlrun/notifications"
    private val gpsChannelName = "io.github.jbinder.sprawlrun/gps"

    /**
     * Hard-coded in geolocator's GeolocatorLocationService. Matching it is the
     * whole point — see [ensureMissionChannel].
     */
    private val missionChannelId = "geolocator_channel_01"

    /**
     * Channels for the messages handlers send between runs. Created here at
     * launch rather than left to the notification plugin, for the same reason
     * [ensureMissionChannel] exists: importance is fixed when a channel is
     * first created and cannot be raised by a later update, so it is worth
     * setting deliberately and once.
     */
    private val reminderChannelId = "signals_reminder"
    private val ambientChannelId = "signals_ambient"
    private val debriefChannelId = "signals_debrief"

    private val notificationRequestCode = 4711

    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }

        val app = context.applicationContext
        // Plugins register themselves from the constructor.
        val engine = FlutterEngine(app)
        installChannels(engine, app)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    /** Decided as the activity goes, from whether a run is in progress. */
    private var destroyEngine = false

    override fun shouldDestroyEngineWithHost(): Boolean = destroyEngine

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        attached = WeakReference(this)
        super.onCreate(savedInstanceState)
        forwardNoticeAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        forwardNoticeAction(intent)
    }

    /**
     * The notification's Stop button opens the app with an extra, so the run
     * screen can ask before ending a run short of its goal. Removed once
     * handled: Android redelivers an activity's intent on recreation, and a
     * rotation must not ask again.
     */
    private fun forwardNoticeAction(intent: Intent?) {
        val action = intent?.getStringExtra(MissionService.EXTRA_NOTICE_ACTION) ?: return
        intent.removeExtra(MissionService.EXTRA_NOTICE_ACTION)
        if (MissionService.running) MissionService.onAction?.invoke(action)
    }

    override fun onResume() {
        attached = WeakReference(this)
        super.onResume()
    }

    override fun onDestroy() {
        // Only here, never as a standing answer: Flutter also asks when a
        // second activity takes the engine over, and answering true then is
        // an AssertionError.
        destroyEngine = !MissionService.running
        val engine = flutterEngine
        if (attached?.get() === this) attached = null
        // A permission dialog left open by an activity that is going would
        // otherwise leave the run start waiting on it for ever.
        pendingNotificationResult?.success(false)
        pendingNotificationResult = null
        super.onDestroy()
        if (destroyEngine && engine != null && FlutterEngineCache.getInstance().get(ENGINE_ID) === engine) {
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        }
    }

    private fun installChannels(flutterEngine: FlutterEngine, app: Context) {
        ensureMissionChannel(app)
        ensureSignalChannels(app)

        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, gpsChannelName)
            .setStreamHandler(GpsStream(app))

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

        val notifications = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannelName)
        // The notification's buttons, into the run. One engine per process, so
        // one listener; it is never cleared, since the engine outlives every
        // activity that attaches to it.
        MissionService.onAction = { action -> notifications.invokeMethod("noticeAction", action) }
        notifications
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        val activity = attached?.get()
                        if (activity == null) {
                            result.success(hasNotificationPermission(app))
                        } else {
                            activity.requestNotificationPermission(result)
                        }
                    }

                    // Every run, GPS or not — see MissionService.
                    "startMissionNotice" -> {
                        MissionService.start(
                            app,
                            call.argument<String>("text") ?: "",
                            call.argument<Boolean>("tracking") ?: false,
                            call.argument<Boolean>("paused") ?: false
                        )
                        result.success(null)
                    }

                    // Same call: the service updates in place once started.
                    "updateMissionNotice" -> {
                        MissionService.start(
                            app,
                            call.argument<String>("text") ?: "",
                            call.argument<Boolean>("tracking") ?: false,
                            call.argument<Boolean>("paused") ?: false
                        )
                        result.success(null)
                    }

                    "stopMissionNotice" -> {
                        MissionService.stop(app)
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
    private fun ensureMissionChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
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
    private fun ensureSignalChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // A reminder is an ordinary notification: whatever sound and vibration
        // the device normally uses. One that cannot be noticed is not a
        // reminder. Nothing is ever spoken aloud — that is the narrator's job
        // and signals never reach it.
        val reminders = NotificationChannel(
            reminderChannelId,
            "Reminders",
            NotificationManager.IMPORTANCE_DEFAULT
        )
        reminders.description = "Your handler, asking whether you are running today."
        manager.createNotificationChannel(reminders)

        // Ambient traffic is flavour, not information, so it never interrupts.
        val ambient = NotificationChannel(
            ambientChannelId,
            "Signal noise",
            NotificationManager.IMPORTANCE_LOW
        )
        ambient.description = "Traffic from the Sprawl. Silent."
        ambient.enableVibration(false)
        ambient.setShowBadge(false)
        manager.createNotificationChannel(ambient)

        // The weekly readout gets its own channel so a runner can keep it while
        // silencing the nudges, or the reverse, in Android's own settings.
        val debrief = NotificationChannel(
            debriefChannelId,
            "Weekly debrief",
            NotificationManager.IMPORTANCE_DEFAULT
        )
        debrief.description = "How your week went, when it closes."
        manager.createNotificationChannel(debrief)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission(this)) {
            result.success(true)
            return
        }
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
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
