package com.lusicgal.engines.web

import android.util.Log
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Locale

/**
 * 本地 HTTP 静态服务器（WebView 跑 Web 引擎用）。
 *
 * 能力（协议参考移植自 xm486/YukiHub GPL-3.0 tyrano/TyranoActivity 内嵌
 * LocalHttpServer，署名见 docs/LICENSE_NOTES.md）：
 *  - 仅绑定 127.0.0.1，GET/HEAD；
 *  - 越界防护（canonical 路径必须落在根内）+ 大小写不敏感回退；
 *  - 资源后缀回退：.m4a→.ogg、.rpgmvm→.rpgmvo（RPG Maker MV 打包惯例）；
 *  - app.asar（Electron）内容读取（根或 resources/ 下）；
 *  - index.html 注入启动 hook（assets/lg_web_boot.js）；
 *  - Range（音频/视频按需拖动必需）。
 */
class LocalWebServer(
    root: File,
    private val asar: AsarArchive?,
    private val hookJs: ByteArray,
) : Runnable {
    private val root: File = root.canonicalFile

    /**
     * 端口固定化（v0.1.8）：localStorage 按 origin 隔离 —— 随机端口 =
     * 每次启动新 origin = 存档全丢（Tyrano v5 直用 localStorage、
     * RPG MV/MZ 存档也全在 localStorage；tyrano 现机实测弹
     * "この環境はセーブ機能を利用できません"）。固定候选序列优先，
     * 全被占才降级随机（此时存档可能丢，属罕见退化）。
     */
    private val serverSocket: ServerSocket = bindStable()

    private fun bindStable(): ServerSocket {
        val loopback = InetAddress.getByName("127.0.0.1")
        for (port in STABLE_PORTS) {
            try {
                return ServerSocket(port, 50, loopback)
            } catch (_: Throwable) {
            }
        }
        return ServerSocket(0, 50, loopback)
    }

    @Volatile private var running = true
    private val thread = Thread(this, "LusicgalWebServer")

    fun start() { thread.isDaemon = true; thread.start() }
    fun port(): Int = serverSocket.localPort
    fun stop() {
        running = false
        try { serverSocket.close() } catch (_: Throwable) {}
    }

    override fun run() {
        Log.i(TAG, "local server started port=${port()} root=$root")
        while (running) {
            try {
                val socket = serverSocket.accept()
                Thread { handle(socket) }.apply { isDaemon = true }.start()
            } catch (t: Throwable) {
                if (running) Log.w(TAG, "accept failed", t)
            }
        }
    }

    private fun handle(socket: Socket) {
        try {
            socket.soTimeout = 15000
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
            val requestLine = reader.readLine() ?: run { close(socket); return }
            val headers = HashMap<String, String>()
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                val idx = line.indexOf(':')
                if (idx > 0) headers[line.substring(0, idx).trim().lowercase(Locale.ROOT)] =
                    line.substring(idx + 1).trim()
            }
            val parts = requestLine.split(" ")
            if (parts.size < 2) { sendText(socket, 400, "Bad Request", "bad request"); return }
            val method = parts[0]
            if (!method.equals("GET", true) && !method.equals("HEAD", true)) {
                sendText(socket, 405, "Method Not Allowed", "method not allowed"); return
            }
            var uri = parts[1]
            val q = uri.indexOf('?')
            if (q >= 0) uri = uri.substring(0, q)
            uri = URLDecoder.decode(uri, "UTF-8")
            if (uri == "/") uri = "/index.html"
            while (uri.startsWith("/")) uri = uri.substring(1)

            val asarBytes = if (uri.contains('\u0000')) null else asar?.read(uri)
            if (asarBytes != null) {
                if (isIndexHtml(uri)) {
                    sendInjectedIndex(socket, asarBytes, method.equals("HEAD", true))
                } else {
                    sendBytes(socket, asarBytes, uri, method.equals("HEAD", true))
                }
                return
            }
            val file = resolveFile(uri) ?: run {
                // index.html 的 asar 常见备选路径。
                if (isIndexHtml(uri)) {
                    for (alt in listOf("index.html", "www/index.html", "app/index.html", "resources/app/index.html")) {
                        val b = asar?.read(alt)
                        if (b != null) { sendInjectedIndex(socket, b, method.equals("HEAD", true)); return }
                    }
                }
                sendText(socket, 404, "Not Found", "not found: $uri"); return
            }
            if (isIndexHtml(uri)) {
                sendInjectedIndex(socket, readAll(file), method.equals("HEAD", true))
            } else {
                sendFile(socket, file, headers["range"], method.equals("HEAD", true))
            }
        } catch (t: Throwable) {
            try { sendText(socket, 500, "Internal Server Error", "server error") } catch (_: Throwable) {}
            Log.w(TAG, "handle request failed", t)
        } finally {
            close(socket)
        }
    }

    /** 越界防护 + 大小写不敏感 + 资源后缀回退。 */
    private fun resolveFile(uri: String): File? {
        canonical(uri)?.let { return it }
        val lower = uri.lowercase(Locale.ROOT)
        if (lower.endsWith(".m4a")) {
            canonical(uri.substring(0, uri.length - 4) + ".ogg")?.let { return it }
        }
        if (lower.endsWith(".rpgmvm")) {
            canonical(uri.substring(0, uri.length - 7) + ".rpgmvo")?.let { return it }
        }
        if (lower.endsWith(".rpgmvo")) {
            canonical(uri.substring(0, uri.length - 7) + ".rpgmvm")?.let { return it }
        }
        // 大小写不敏感逐段回退。
        if (uri.contains("..").not() && uri.isNotEmpty()) {
            var current = root
            for (part in uri.split("/")) {
                if (part.isEmpty()) continue
                val exact = File(current, part)
                current = if (exact.exists()) exact else {
                    val children = current.listFiles() ?: return null
                    children.firstOrNull { it.name.equals(part, ignoreCase = true) } ?: return null
                }
            }
            val target = current.canonicalFile
            if (target.path.startsWith(root.path) && target.isFile) return target
        }
        return null
    }

    private fun canonical(uri: String): File? {
        if (uri.isEmpty() || uri.contains('\u0000')) return null
        return try {
            val target = File(root, uri).canonicalFile
            if (target.path.startsWith(root.path) && target.isFile) target else null
        } catch (t: Throwable) { null }
    }

    private fun isIndexHtml(uri: String): Boolean {
        val lower = uri.lowercase(Locale.ROOT)
        return lower.endsWith("index.html") || lower.endsWith("index.htm")
    }

    private fun sendInjectedIndex(socket: Socket, htmlBytes: ByteArray, headOnly: Boolean) {
        var html = String(htmlBytes, StandardCharsets.UTF_8)
        val script = if (hookJs.isNotEmpty()) String(hookJs, StandardCharsets.UTF_8) else ""
        val injected = "\n<script type='text/javascript'>\n$script\n</script>\n"
        val lower = html.lowercase(Locale.ROOT)
        val pos = lower.indexOf("</head>")
        html = if (pos >= 0) html.substring(0, pos) + injected + html.substring(pos)
        else injected + html
        val data = html.toByteArray(StandardCharsets.UTF_8)
        val out = BufferedOutputStream(socket.getOutputStream())
        out.write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-cache\r\nContent-Length: ${data.size}\r\nConnection: close\r\n\r\n".toByteArray())
        if (!headOnly) out.write(data)
        out.flush()
    }

    private fun sendBytes(socket: Socket, data: ByteArray, uri: String, headOnly: Boolean) {
        val out = BufferedOutputStream(socket.getOutputStream())
        out.write("HTTP/1.1 200 OK\r\nContent-Type: ${mime(uri)}\r\nContent-Length: ${data.size}\r\nConnection: close\r\n\r\n".toByteArray())
        if (!headOnly) out.write(data)
        out.flush()
    }

    /** 单段 Range 支持（音频/视频拖动必需）。 */
    private fun sendFile(socket: Socket, file: File, rangeHeader: String?, headOnly: Boolean) {
        val length = file.length()
        var from = 0L
        var to = length - 1
        var status = "200 OK"
        if (rangeHeader != null && rangeHeader.startsWith("bytes=")) {
            val spec = rangeHeader.substring(6)
            val dash = spec.indexOf('-')
            if (dash > 0) {
                val f = spec.substring(0, dash).toLongOrNull()
                val t = if (dash + 1 < spec.length) spec.substring(dash + 1).toLongOrNull() else null
                if (f != null && f < length) {
                    from = f
                    to = (t ?: (length - 1)).coerceAtMost(length - 1)
                    status = "206 Partial Content"
                }
            }
        }
        val out = BufferedOutputStream(socket.getOutputStream())
        val contentRange = if (status == "206 Partial Content") {
            "Content-Range: bytes $from-$to/$length\r\n"
        } else {
            ""
        }
        val header = "HTTP/1.1 $status\r\nContent-Type: ${mime(file.name)}\r\n" +
            "Accept-Ranges: bytes\r\n" + contentRange +
            "Content-Length: ${to - from + 1}\r\nConnection: close\r\n\r\n"
        out.write(header.toByteArray(StandardCharsets.UTF_8))
        if (!headOnly) {
            val input = BufferedInputStream(file.inputStream())
            try {
                input.skip(from)
                var remaining = to - from + 1
                val buf = ByteArray(32 * 1024)
                while (remaining > 0) {
                    val n = input.read(buf, 0, minOf(buf.size.toLong(), remaining).toInt())
                    if (n < 0) break
                    out.write(buf, 0, n)
                    remaining -= n
                }
            } finally {
                try { input.close() } catch (_: Throwable) {}
            }
        }
        out.flush()
    }

    private fun sendText(socket: Socket, code: Int, label: String, body: String) {
        val data = body.toByteArray(StandardCharsets.UTF_8)
        val out = BufferedOutputStream(socket.getOutputStream())
        out.write("HTTP/1.1 $code $label\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: ${data.size}\r\nConnection: close\r\n\r\n".toByteArray())
        out.write(data)
        out.flush()
    }

    private fun close(socket: Socket) {
        try { socket.close() } catch (_: Throwable) {}
    }

    private fun readAll(file: File): ByteArray = file.readBytes()

    private fun mime(name: String): String {
        val lower = name.lowercase(Locale.ROOT)
        return when {
            lower.endsWith(".html") || lower.endsWith(".htm") -> "text/html; charset=utf-8"
            lower.endsWith(".js") -> "application/javascript"
            lower.endsWith(".css") -> "text/css"
            lower.endsWith(".json") -> "application/json"
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".svg") -> "image/svg+xml"
            lower.endsWith(".ogg") || lower.endsWith(".oga") -> "audio/ogg"
            lower.endsWith(".m4a") -> "audio/mp4"
            lower.endsWith(".mp3") -> "audio/mpeg"
            lower.endsWith(".wav") -> "audio/wav"
            lower.endsWith(".mp4") || lower.endsWith(".webm") -> "video/${if (lower.endsWith(".mp4")) "mp4" else "webm"}"
            lower.endsWith(".rpgmvp") || lower.endsWith("_p.png") -> "image/png"
            lower.endsWith(".rpgmvo") || lower.endsWith("_o.ogg") -> "audio/ogg"
            lower.endsWith(".rpgmvm") || lower.endsWith("_m.mp4") -> "video/mp4"
            lower.endsWith(".woff") -> "font/woff"
            lower.endsWith(".woff2") -> "font/woff2"
            lower.endsWith(".ttf") -> "font/ttf"
            lower.endsWith(".ks") || lower.endsWith(".csv") || lower.endsWith(".txt") -> "text/plain; charset=utf-8"
            else -> "application/octet-stream"
        }
    }

    companion object {
        private const val TAG = "LusicgalWebServer"

        /** 固定端口候选（origin 稳定性 = localStorage 存档持续性）。 */
        private val STABLE_PORTS = intArrayOf(38765, 38766, 38767, 38768, 38769)
    }
}
