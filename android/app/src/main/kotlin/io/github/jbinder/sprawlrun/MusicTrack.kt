package io.github.jbinder.sprawlrun

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.os.Process
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Plays the PCM a song is generated into, on a thread of its own.
 *
 * Takes no audio focus: that is AudioNarrator's alone. Volume changes happen
 * here rather than in the synth, because what the synth makes now is heard about
 * four seconds from now, and a story line can't wait for that.
 */
class MusicTrack {
    private val queue = LinkedBlockingQueue<ByteArray>()
    private val pending = AtomicLong(0)
    private val main = Handler(Looper.getMainLooper())
    private var track: AudioTrack? = null
    private var writer: Thread? = null
    @Volatile private var running = false
    @Volatile private var paused = false

    private var volume = 1f
    private var ducked = false
    private var gain = 0f
    private var ramp: Runnable? = null

    fun start() {
        release()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
            .build()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val minimum = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val created = AudioTrack(
            attributes,
            format,
            maxOf(minimum * 2, RATE),
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        )
        track = created
        ducked = false
        gain = target()
        created.setVolume(gain)
        paused = false
        running = true
        writer = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            try {
                feed(created)
            } catch (_: InterruptedException) {
                // Stopping.
            } catch (_: IllegalStateException) {
                // Released under a blocking write: also stopping.
            }
        }, "music-track").also { it.start() }
    }

    /**
     * A slice at a time, so a pause lands within a few milliseconds of a bar.
     *
     * A pause keeps the track running on silence, with a short fade each way,
     * rather than calling `AudioTrack.pause`. Stopping and restarting the track
     * made the first notes after a pause rush through on a real phone.
     *
     * Playback starts only once there is sound to play, or the wait for the first
     * bar counts as an underrun.
     */
    private fun feed(out: AudioTrack) {
        val slice = ByteArray(SLICE_BYTES)
        val silence = ByteArray(SLICE_BYTES)
        var chunk: ByteArray? = null
        var at = 0
        var fade = 1.0
        var started = false
        while (running) {
            if (paused && fade <= 0.0) {
                out.write(silence, 0, silence.size, AudioTrack.WRITE_BLOCKING)
                continue
            }
            val current = chunk ?: queue.poll(POLL_MS, TimeUnit.MILLISECONDS)
            if (current == null) continue
            chunk = current
            val count = minOf(SLICE_BYTES, current.size - at)
            System.arraycopy(current, at, slice, 0, count)
            fade = applyFade(slice, count, fade, if (paused) 0.0 else 1.0)
            out.write(slice, 0, count, AudioTrack.WRITE_BLOCKING)
            if (!started) {
                out.play()
                started = true
            }
            at += count
            pending.addAndGet(-count.toLong())
            if (at == current.size) {
                chunk = null
                at = 0
            }
        }
    }

    /** Moves [from] towards [to] across 16-bit stereo [bytes], returning where it got. */
    private fun applyFade(bytes: ByteArray, count: Int, from: Double, to: Double): Double {
        if (from == to && to == 1.0) return from
        var gain = from
        val step = if (to > from) FADE_STEP else -FADE_STEP
        var i = 0
        while (i + 3 < count) {
            gain = if (step > 0) minOf(to, gain + step) else maxOf(to, gain + step)
            for (at in intArrayOf(i, i + 2)) {
                val sample = (bytes[at].toInt() and 0xff) or (bytes[at + 1].toInt() shl 8)
                val faded = (sample * gain).toInt()
                bytes[at] = faded.toByte()
                bytes[at + 1] = (faded shr 8).toByte()
            }
            i += 4
        }
        return gain
    }

    fun write(bytes: ByteArray) {
        if (!running) return
        pending.addAndGet(bytes.size.toLong())
        queue.put(bytes)
    }

    fun queuedMs(): Int = (pending.get() / BYTES_PER_MS).toInt()

    fun underruns(): Int = track?.underrunCount ?: 0

    fun pause() {
        paused = true
    }

    fun resume() {
        paused = false
    }

    fun setDucked(value: Boolean) {
        ducked = value
        rampTo(target(), DUCK_MS)
    }

    fun setVolume(value: Float) {
        volume = value
        rampTo(target(), DUCK_MS)
    }

    /** Fades out and lets go of the track, then calls [done]. */
    fun stop(done: () -> Unit) {
        if (track == null) {
            done()
            return
        }
        rampTo(0f, FADE_MS) {
            release()
            done()
        }
    }

    private fun target() = volume * (if (ducked) DUCK_GAIN else 1f)

    /** Runs on the main thread, as every call from Dart does. */
    private fun rampTo(to: Float, ms: Int, done: (() -> Unit)? = null) {
        ramp?.let { main.removeCallbacks(it) }
        val from = gain
        val steps = maxOf(1, ms / STEP_MS)
        var step = 0
        val tick = object : Runnable {
            override fun run() {
                step++
                gain = from + (to - from) * step / steps
                track?.setVolume(gain)
                if (step < steps) {
                    main.postDelayed(this, STEP_MS.toLong())
                } else {
                    ramp = null
                    done?.invoke()
                }
            }
        }
        ramp = tick
        main.post(tick)
    }

    private fun release() {
        ramp?.let { main.removeCallbacks(it) }
        ramp = null
        running = false
        val thread = writer
        writer = null
        val old = track
        track = null
        old?.pause()
        old?.flush()
        thread?.interrupt()
        thread?.join(JOIN_MS)
        old?.release()
        queue.clear()
        pending.set(0)
    }

    private companion object {
        const val RATE = 44100
        const val BYTES_PER_MS = RATE * 4 / 1000.0
        const val DUCK_GAIN = 0.2f
        const val DUCK_MS = 250
        const val FADE_MS = 400
        const val STEP_MS = 20
        const val JOIN_MS = 200L
        const val POLL_MS = 50L
        const val SLICE_BYTES = 4096
        const val FADE_STEP = 1.0 / (RATE / 10)
    }
}
