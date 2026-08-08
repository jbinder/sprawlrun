package io.github.jbinder.sprawlrun

import android.content.Context
import android.media.AudioManager
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Adds the two audio calls that let the app repair a failed focus handoff.
 *
 * Android's transient audio focus is a loan: the music app pauses when we take
 * it and is supposed to resume when we give it back. Several popular players
 * only honour that for short interruptions and stay silent after a long one.
 * There is no way to fix that from inside our own focus request, so the app
 * detects the failure and presses PLAY on the runner's behalf.
 *
 * Neither call needs a permission, and neither can reach the network.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "io.github.jbinder.sprawlrun/audio"

    private val audio: AudioManager
        get() = getSystemService(Context.AUDIO_SERVICE) as AudioManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
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
    }
}
