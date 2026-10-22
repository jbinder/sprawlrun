package io.github.jbinder.sprawlrun

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.Executors

/**
 * The folder automatic backups are written to, chosen once by the runner.
 *
 * The choice is Android's own persisted permission on a document tree, not a
 * setting of ours: it is the one thing that lets the app write there again
 * after a restart, and keeping the folder anywhere else could only drift from
 * it. So it never travels in a backup either — a restore on another phone
 * starts with no folder rather than one it cannot write to. Turning automatic
 * backups off releases the permission.
 *
 * No storage permission is involved, and the app can see nothing in the folder
 * but what it wrote: the system picker grants this one tree and nothing else.
 */
class BackupFolder(private val context: Context) {
    private val resolver get() = context.contentResolver

    /** Disk and provider calls stay off the main thread; results go back to it. */
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The chosen tree, if a permission to write to one is still held. */
    fun current(): Uri? = resolver.persistedUriPermissions
        .firstOrNull { it.isWritePermission && DocumentsContract.isTreeUri(it.uri) }
        ?.uri

    /** The folder's own name, as the runner saw it in the picker. */
    fun name(tree: Uri): String? = try {
        resolver.query(root(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (e: Exception) {
        // A folder deleted since, or a provider that went away.
        null
    }

    /** Keeps [tree] across restarts and lets go of any folder chosen before. */
    fun keep(tree: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        resolver.takePersistableUriPermission(tree, flags)
        for (held in resolver.persistedUriPermissions) {
            if (held.uri != tree && DocumentsContract.isTreeUri(held.uri)) release(held.uri)
        }
    }

    fun forget() {
        for (held in resolver.persistedUriPermissions) {
            if (DocumentsContract.isTreeUri(held.uri)) release(held.uri)
        }
    }

    private fun release(uri: Uri) {
        resolver.releasePersistableUriPermission(
            uri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
    }

    /**
     * Writes [bytes] as a new file called [fileName], then deletes all but the
     * [keep] newest files starting with [prefix]. The new file is complete
     * before anything old is deleted, so a write that fails never costs the
     * last good copy; a half-written file is removed again.
     */
    fun write(fileName: String, bytes: ByteArray, prefix: String, keep: Int, result: MethodChannel.Result) {
        val tree = current()
        if (tree == null) {
            result.error("noFolder", "No backup folder is chosen", null)
            return
        }
        io.execute {
            try {
                val doc = DocumentsContract.createDocument(resolver, root(tree), "application/json", fileName)
                    ?: throw IOException("could not create $fileName")
                try {
                    (resolver.openOutputStream(doc, "w") ?: throw IOException("could not open $fileName"))
                        .use { it.write(bytes) }
                } catch (e: Exception) {
                    DocumentsContract.deleteDocument(resolver, doc)
                    throw e
                }
                prune(tree, prefix, keep)
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("writeFailed", e.message ?: e.toString(), null) }
            }
        }
    }

    /** Only the app's own files: anything else in the folder is the runner's. */
    private fun prune(tree: Uri, prefix: String, keep: Int) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val ours = mutableListOf<Pair<String, String>>()
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use {
            while (it.moveToNext()) {
                val name = it.getString(1) ?: continue
                if (name.startsWith(prefix)) ours.add(it.getString(0) to name)
            }
        }
        // The names carry the date, so they sort oldest first.
        for ((id, _) in ours.sortedByDescending { it.second }.drop(keep)) {
            DocumentsContract.deleteDocument(resolver, DocumentsContract.buildDocumentUriUsingTree(tree, id))
        }
    }

    private fun root(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
}
