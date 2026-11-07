package io.github.jbinder.sprawlrun

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** A folder the runner picks in the system's own picker. */
interface ChosenFolder {
    /** What the picker is asked to grant. */
    val grantFlags: Int

    /** Keeps [tree] across restarts and lets go of any folder chosen before. */
    fun keep(tree: Uri)

    fun name(tree: Uri): String?
}

/**
 * The folder music is played from, read and nothing else.
 *
 * Like the backup folder, the choice is Android's persisted permission, so it
 * never travels in a backup: a restore on another phone starts with no folder.
 * Which of the held permissions is this one needs a note of its own, since the
 * same tree can also be the backup folder, and then Android holds one grant for
 * both. So letting go of it only ever gives up what the backup folder isn't using.
 */
class MusicFolder(private val context: Context) : ChosenFolder {
    private val resolver get() = context.contentResolver
    private val prefs get() = context.getSharedPreferences("music_folder", Context.MODE_PRIVATE)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override val grantFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION

    /** The chosen tree, if a permission to read it is still held. */
    fun current(): Uri? {
        val stored = prefs.getString(KEY, null)?.let(Uri::parse) ?: return null
        return stored.takeIf { resolver.persistedUriPermissions.any { held -> held.uri == stored && held.isReadPermission } }
    }

    override fun name(tree: Uri): String? = try {
        resolver.query(root(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    override fun keep(tree: Uri) {
        resolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val before = prefs.getString(KEY, null)?.let(Uri::parse)
        prefs.edit().putString(KEY, tree.toString()).apply()
        if (before != null && before != tree) release(before)
    }

    fun forget() {
        val before = prefs.getString(KEY, null)?.let(Uri::parse) ?: return
        prefs.edit().remove(KEY).apply()
        release(before)
    }

    private fun release(tree: Uri) {
        // A grant that can also write belongs to the backup folder too.
        val shared = resolver.persistedUriPermissions.any { it.uri == tree && it.isWritePermission }
        if (!shared) {
            try {
                resolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            } catch (e: SecurityException) {
                // Already gone.
            }
        }
    }

    /**
     * The folder's audio files, top level only, as `{uri, name}`. An empty list,
     * not an error, when the folder has gone: a run goes ahead without music.
     */
    fun list(result: MethodChannel.Result) {
        val tree = current()
        if (tree == null) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        io.execute {
            val tracks = mutableListOf<Map<String, String>>()
            try {
                val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                resolver.query(
                    children,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_MIME_TYPE
                    ),
                    null, null, null
                )?.use {
                    while (it.moveToNext()) {
                        val name = it.getString(1) ?: continue
                        val mime = it.getString(2) ?: ""
                        if (!isAudio(name, mime)) continue
                        val document = DocumentsContract.buildDocumentUriUsingTree(tree, it.getString(0))
                        tracks.add(mapOf("uri" to document.toString(), "name" to name))
                    }
                }
            } catch (e: Exception) {
                tracks.clear()
            }
            main.post { result.success(tracks) }
        }
    }

    /** Some providers call everything application/octet-stream, so the name counts too. */
    private fun isAudio(name: String, mime: String) =
        mime.startsWith("audio/") || name.substringAfterLast('.', "").lowercase() in AUDIO_EXTENSIONS

    private fun root(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    companion object {
        private const val KEY = "tree"
        private val AUDIO_EXTENSIONS = setOf("mp3", "m4a", "aac", "ogg", "oga", "opus", "flac", "wav", "mka", "weba")
    }
}
