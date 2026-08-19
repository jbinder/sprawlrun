package io.github.jbinder.sprawlrun

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Holds a run in the foreground and owns its notification, for every mission.
 *
 * It exists because geolocator's service could not do the whole job. That one
 * only runs when there is a GPS session, so a mission started with location off
 * had nothing in the foreground at all — no notice, and nothing stopping Android
 * freezing the process in a pocket, which stalls the ticker that fires the story
 * beats. Its notification text is also fixed for the life of the stream, so it
 * could never count anything down.
 *
 * So the app runs its own instead, and `location_service.dart` no longer passes
 * geolocator a notification config. The service type follows the run: `location`
 * when the runner granted it, which is what lets fixes keep arriving with the
 * screen off, and `specialUse` when there is no location to claim — Android 14+
 * rejects a `location` service started without the permission.
 *
 * The partial wake lock is not redundant with being in the foreground: a
 * foreground service does not keep the CPU awake by itself.
 */
class MissionService : Service() {
    companion object {
        /** geolocator's channel id. Shared on purpose: one "Active mission"
         *  entry in system settings whichever service is running, and
         *  MainActivity has already created it at IMPORTANCE_LOW. */
        const val CHANNEL_ID = "geolocator_channel_01"

        /** geolocator uses 75415. Distinct so the two can never collide. */
        const val NOTIFICATION_ID = 75416

        private const val WAKE_LOCK_TAG = "sprawlrun:mission"

        /** A backstop, not a policy. The service releases the lock when the run
         *  ends; this only bounds the damage if something leaks it. Longer than
         *  any plausible run. */
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000

        const val EXTRA_TEXT = "text"
        const val EXTRA_TRACKING = "tracking"

        /** [tracking] is whether the run has location — it decides the service
         *  type, and Android will not let that be claimed without the grant. */
        fun start(context: Context, text: String, tracking: Boolean) {
            val intent = Intent(context, MissionService::class.java)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_TRACKING, tracking)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MissionService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var started = false

    /** Whether the foreground type currently asserted is `location`. A run that
     *  starts before its readiness is known opens as a plain timer and is
     *  promoted once the answer arrives. */
    private var claimedLocation = false

    /** Shown for the instant before the first tick arrives. */
    private val defaultText get() = "Mission active — keep moving."

    private fun serviceType(tracking: Boolean): Int =
        if (tracking) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: defaultText
        val tracking = intent?.getBooleanExtra(EXTRA_TRACKING, false) ?: false

        if (started && tracking == claimedLocation) {
            // A tick, not a new run and not a change of type. notify() replaces
            // the notification in place for a fraction of the cost.
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, buildNotification(text))
            return START_NOT_STICKY
        }

        // Either the first call, or the run has learned it has location after
        // opening as a plain timer. startForeground is what asserts the type,
        // and it is safe to call again on a service already in the foreground.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, buildNotification(text), serviceType(tracking))
        } else {
            startForeground(NOTIFICATION_ID, buildNotification(text))
        }
        started = true
        claimedLocation = tracking
        acquireWakeLock()
        // Not START_STICKY: a mission the system killed should not come back as
        // an empty notification with no run behind it.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        started = false
        claimedLocation = false
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiping the app away ends the run; leaving the notice behind would
        // advertise a mission that is no longer being timed.
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun buildNotification(text: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SPRAWL//RUN")
            // Written by the run itself — remaining time or distance, pushed
            // on every tick that changes it.
            .setContentText(text)
            // R.drawable, not getIdentifier: a static reference is one the
            // resource shrinker can see. A mipmap launcher icon would render as
            // a white blob anyway — the system reads nothing but alpha here.
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(buildBringToFrontIntent())
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            // Android 12+ holds a foreground-service notification back for up
            // to ten seconds unless it is told not to. For a run that is ten
            // seconds of the runner wondering whether the mission started.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun buildBringToFrontIntent(): PendingIntent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        intent.setPackage(null)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
