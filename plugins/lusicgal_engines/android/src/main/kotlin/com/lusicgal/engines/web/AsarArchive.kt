package com.lusicgal.engines.web

import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets

/**
 * Electron ASAR 容器最小读取器（TyranoBuilder 桌面导出 / NW.js 包）。
 *
 * 布局（Tyranor 的 F0.e 同构）：magic(4)=4 → headerSize(u32) →
 * dataOffset = 8 + headerSize → 4 字节保留 → jsonLen(u32) → header JSON。
 *
 * 移植自 xm486/YukiHub（GPL-3.0）tyrano/AsarArchive.java，署名见
 * docs/LICENSE_NOTES.md。
 */
class AsarArchive(file: File) {
    private val archiveFile: File = file.canonicalFile
    private val raf = RandomAccessFile(archiveFile, "r")
    private val dataOffset: Long
    private val entries = HashMap<String, Entry>()

    init {
        require(raf.readUInt32LE().toInt() == 4) { "not asar file" }
        val headerSize = raf.readUInt32LE()
        dataOffset = 8L + headerSize
        raf.skipBytes(4)
        val jsonLen = raf.readUInt32LE()
        val jsonBytes = ByteArray(jsonLen.toInt())
        raf.readFully(jsonBytes)
        parseNode("", JSONObject(String(jsonBytes, StandardCharsets.UTF_8)))
        Log.i(TAG, "asar loaded entries=${entries.size} dataOffset=$dataOffset")
    }

    fun read(path: String): ByteArray? {
        return try {
            val e = entries[normalize(path)] ?: return null
            if (e.directory) return null
            val data = ByteArray(e.size.toInt())
            synchronized(raf) {
                raf.seek(dataOffset + e.offset)
                raf.readFully(data)
            }
            data
        } catch (t: Throwable) {
            Log.w(TAG, "read failed path=$path", t)
            null
        }
    }

    private fun parseNode(prefix: String, node: JSONObject) {
        val files = node.optJSONObject("files")
        if (files == null) {
            if (prefix.isNotEmpty()) {
                entries[normalize(prefix)] =
                    Entry(false, node.optString("size", "0").toLongOr0(), node.optString("offset", "0").toLongOr0())
            }
            return
        }
        if (prefix.isNotEmpty()) entries[normalize(prefix)] = Entry(true, 0, 0)
        for (name in files.keys()) {
            val child = files.optJSONObject(name) ?: continue
            parseNode(if (prefix.isEmpty()) name else "$prefix/$name", child)
        }
    }

    private class Entry(val directory: Boolean, val size: Long, val offset: Long)

    companion object {
        private const val TAG = "LusicgalAsar"

        fun normalize(path: String?): String {
            var p = path?.trim()?.replace('\\', '/') ?: return ""
            while (p.startsWith("/")) p = p.substring(1)
            return p
        }

        private fun RandomAccessFile.readUInt32LE(): Long {
            val b1 = read().toLong()
            val b2 = read().toLong()
            val b3 = read().toLong()
            val b4 = read().toLong()
            if (b1 or b2 or b3 or b4 < 0) throw java.io.EOFException()
            return (b4 shl 24) or (b3 shl 16) or (b2 shl 8) or b1
        }

        private fun String.toLongOr0(): Long =
            toLongOrNull() ?: 0L
    }
}
