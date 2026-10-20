package com.lusicgal.engines.web

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.Toast
import java.io.File

/**
 * Web 引擎运行页（TyranoScript / RPG Maker MV / MZ）。
 *
 * 跑法（参考 xm486/YukiHub GPL-3.0 tyrano/TyranoActivity 架构并重写，
 * 署名见 docs/LICENSE_NOTES.md）：
 *  - 本地 HTTP 服务（[LocalWebServer]）供文件 + index.html 注入启动 hook
 *    （assets/lg_web_boot.js：按运行时特征自适应 Tyrano / MV / MZ，
 *    提供音频暂停/恢复与虚拟按键合成）；
 *  - WebView 全屏；DOM storage 持久化存档（应用数据目录内）；
 *  - RPG MV/MZ 叠加虚拟手柄（引擎用键盘交互），经 JS 合成 KeyboardEvent；
 *  - Tyrano 桌面导出（app.asar）经 [AsarArchive] 读取。
 *
 * 入口 extras：gameDir（游戏目录）、kind（tyrano|rpgmv|rpgmz）、
 * saveDir（localStorage 重定向落盘点，空则用默认 DOM storage）。
 */
class WebGameActivity : Activity() {
    private var gameDir: String? = null
    private var kind: String = "tyrano"
    private var saveDir: String? = null
    private var server: LocalWebServer? = null
    private var webView: WebView? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        gameDir = intent.getStringExtra("gameDir")
        kind = intent.getStringExtra("kind") ?: "tyrano"
        saveDir = intent.getStringExtra("saveDir")

        val dir = gameDir
        if (dir.isNullOrBlank() || !File(dir).isDirectory) {
            finish()
            return
        }
        val root = File(dir)
        var asar: AsarArchive? = null
        for (candidate in listOf(File(root, "app.asar"), File(root, "resources/app.asar"))) {
            if (candidate.isFile) {
                try {
                    asar = AsarArchive(candidate)
                } catch (t: Throwable) {
                    Log.w(TAG, "open asar failed", t)
                }
                break
            }
        }

        val hook = try {
            assets.open("lg_web_boot.js").use { it.readBytes() }
        } catch (t: Throwable) {
            Log.w(TAG, "read hook asset failed", t)
            ByteArray(0)
        }

        // 本地 HTTP 服务是 Web 引擎的命脉（2026-10-19 修复：release 包缺
        // INTERNET 权限时 ServerSocket(127.0.0.1) 直接 EACCES 崩掉本页 ——
        // 现已补权限，此处再兜底：任何启动异常以 Toast 提示后温和退出）。
        val srv = try {
            val s = LocalWebServer(root, asar, hook)
            s.start()
            s
        } catch (t: Throwable) {
            Log.e(TAG, "本地服务启动失败：$t")
            try {
                Toast.makeText(
                    this, "本地服务启动失败：${t.message}", Toast.LENGTH_LONG
                ).show()
            } catch (_: Throwable) {
            }
            finish()
            return
        }
        server = srv

        val rootLayout = FrameLayout(this)
        rootLayout.setBackgroundColor(Color.BLACK)

        val wv = WebView(this)
        wv.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
        )
        if (Build.VERSION.SDK_INT >= 26) wv.defaultFocusHighlightEnabled = false
        val s: WebSettings = wv.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true   // 存档：DOM storage 落在应用数据目录（持久）
        s.databaseEnabled = true
        s.allowFileAccess = true
        s.allowContentAccess = true
        s.mediaPlaybackRequiresUserGesture = false
        s.setSupportZoom(false)
        wv.addJavascriptInterface(WebBridge(), "lusicgalBridge")
        wv.webChromeClient = WebChromeClient()
        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                handleExternalUrl(request.url.toString())

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                handleExternalUrl(url)
        }
        rootLayout.addView(wv)
        webView = wv

        if (kind == "rpgmv" || kind == "rpgmz") {
            rootLayout.addView(buildGamepad(wv))
        }

        setContentView(rootLayout)
        wv.loadUrl("http://localhost:${srv.port()}/index.html")
    }

    /** 外部 http(s) 链接转系统浏览器；本地资源放行。 */
    private fun handleExternalUrl(url: String): Boolean {
        if (url.startsWith("http://localhost:") || url.startsWith("http://127.0.0.1:")) {
            return false
        }
        return try {
            startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)))
            true
        } catch (t: Throwable) {
            false
        }
    }

    /** 虚拟手柄（RPG MV/MZ 的键盘交互）：按键经 JS 合成 KeyboardEvent。 */
    private fun buildGamepad(wv: WebView): View {
        val overlay = FrameLayout(this)
        val dpad = FrameLayout(this)
        dpad.layoutParams = FrameLayout.LayoutParams(340, 340).apply {
            gravity = Gravity.BOTTOM or Gravity.START
            leftMargin = 24
            bottomMargin = 24
        }
        fun keyButton(label: String, code: String, size: Int, l: Int, t: Int, r: Int, b: Int): Button {
            val btn = Button(this)
            btn.text = label
            btn.setTextColor(Color.WHITE)
            btn.setBackgroundColor(0x66333333)
            val lp = FrameLayout.LayoutParams(size, size).apply {
                leftMargin = l; topMargin = t; rightMargin = r; bottomMargin = b
            }
            btn.layoutParams = lp
            btn.setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        wv.evaluateJavascript("__lgKey('$code','keydown')", null); true
                    }
                    android.view.MotionEvent.ACTION_UP, android.view.MotionEvent.ACTION_CANCEL -> {
                        wv.evaluateJavascript("__lgKey('$code','keyup')", null); true
                    }
                    else -> false
                }
            }
            return btn
        }
        dpad.addView(keyButton("↑", "ArrowUp", 100, 120, 0, 120, 240))
        dpad.addView(keyButton("↓", "ArrowDown", 100, 120, 240, 120, 0))
        dpad.addView(keyButton("←", "ArrowLeft", 100, 0, 120, 240, 120))
        dpad.addView(keyButton("→", "ArrowRight", 100, 240, 120, 0, 120))
        overlay.addView(dpad)

        val actions = FrameLayout(this)
        actions.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            rightMargin = 24
            bottomMargin = 24
        }
        actions.addView(keyButton("OK", "Enter", 150, 0, 0, 170, 0))
        actions.addView(keyButton("✕", "Escape", 150, 170, 0, 0, 0))
        overlay.addView(actions)
        return overlay
    }

    public override fun onPause() {
        webView?.evaluateJavascript("__lgAudioPause()", null)
        super.onPause()
    }

    public override fun onResume() {
        super.onResume()
        webView?.evaluateJavascript("__lgAudioResume()", null)
    }

    override fun onDestroy() {
        server?.stop()
        webView?.apply {
            loadUrl("about:blank")
            destroy()
        }
        webView = null
        super.onDestroy()
    }

    /** JS 桥：Tyrano 存档落盘重定向 + 外部链接。 */
    private inner class WebBridge {
        @JavascriptInterface
        fun setStorage(key: String, value: String) {
            val dir = File(saveDir ?: File(filesDir, "web_saves/${kind}").apply { mkdirs() }.path)
            try {
                dir.mkdirs()
                File(dir, "$key.sav").writeText(value)
            } catch (t: Throwable) {
                Log.w(TAG, "setStorage failed key=$key", t)
            }
        }

        @JavascriptInterface
        fun getStorage(key: String): String =
            try {
                val dir = File(saveDir ?: File(filesDir, "web_saves/${kind}").path)
                File(dir, "$key.sav").readText()
            } catch (t: Throwable) {
                ""
            }

        @JavascriptInterface
        fun openUrl(url: String) {
            try {
                startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url)))
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "LusicgalWebGame"

        /** 由插件启动（避免插件侧直接依赖 Activity 类名的耦合）。 */
        fun start(context: android.content.Context, gameDir: String, kind: String, saveDir: String?) {
            val intent = android.content.Intent(context, WebGameActivity::class.java).apply {
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("gameDir", gameDir)
                putExtra("kind", kind)
                putExtra("saveDir", saveDir)
            }
            context.startActivity(intent)
        }
    }
}
