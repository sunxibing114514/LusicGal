package com.lusicgal.engines

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * 只读文件提供器：把 App 沙盒内的游戏文件以 content:// URI 授权给外部应用
 * （PPSSPP 等以独立 UID 运行，读不到本应用私有目录 —— Android 11+ FUSE
 * 强制隔离；content:// + FLAG_GRANT_READ_URI_PERMISSION 是标准解法，
 * PPSSPP 同时支持 file 与 content scheme）。
 *
 * URI 形态：content://com.lusicgal.games/<候选根序号>/<相对路径>
 * 候选根 = 应用实际可能存放游戏的两个文档根（path_provider 的
 * getApplicationDocumentsDirectory 在 Android 落在这两者之一）：
 *   1 = context.getExternalFilesDir(null)（/storage/emulated/0/Android/data/<pkg>/files）
 *   2 = context.filesDir（/data/user/0/<pkg>/files）
 * 越界防护：解析出的 canonical 路径必须仍在对应根内。
 */
class LusicgalGamesProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    private fun roots(): List<File> {
        val ctx = context ?: return emptyList()
        return listOfNotNull(ctx.getExternalFilesDir(null), ctx.filesDir)
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        if (mode != "r") throw SecurityException("read only: $mode")
        val segs = uri.pathSegments
        if (segs.size < 2) throw IllegalArgumentException("bad uri: $uri")
        val rootIdx = segs[0].toIntOrNull() ?: throw IllegalArgumentException("bad root: ${segs[0]}")
        val root = roots().getOrNull(rootIdx) ?: throw IllegalArgumentException("root missing")
        val rel = segs.subList(1, segs.size).joinToString("/")
        if (rel.contains("..")) throw SecurityException("traversal: $rel")
        val f = File(root, rel)
        val canonical = try { f.canonicalFile } catch (t: Throwable) { null }
            ?: throw IllegalArgumentException("unresolvable")
        if (!canonical.path.startsWith(root.canonicalPath) || !canonical.isFile) {
            throw SecurityException("outside root or missing: $rel")
        }
        return ParcelFileDescriptor.open(canonical, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String =
        when (uri.lastPathSegment?.lowercase()?.substringAfterLast('.')) {
            "iso", "cso", "chd", "pbp" -> "application/octet-stream"
            else -> "application/octet-stream"
        }

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?
    ): Int = 0

    companion object {
        const val AUTHORITY = "com.lusicgal.games"

        /**
         * [absolutePath]（App 沙盒内）→ 授权 content URI。
         * 路径不在任一候选根下时返回 null（调用方回退 file://）。
         */
        fun toContentUri(context: android.content.Context, absolutePath: String): Uri? {
            val roots = listOfNotNull(
                context.getExternalFilesDir(null),
                context.filesDir,
            )
            for ((idx, root) in roots.withIndex()) {
                val rootPath = root.canonicalPath
                val target = try {
                    File(absolutePath).canonicalPath
                } catch (t: Throwable) {
                    return null
                }
                if (target == rootPath || target.startsWith(rootPath + File.separator)) {
                    val rel = target.substring(rootPath.length).trimStart('/')
                    return Uri.parse("content://$AUTHORITY/$idx/$rel")
                }
            }
            return null
        }
    }
}
