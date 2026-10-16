package com.lusicgal.engines

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * 外板启动器：PSP（PPSSPP）/ PC（winlator-cn 外置启动协议）/ 安装的应用条目。
 *
 * 协议来源（移植自 xm486/YukiHub GPL-3.0，launcher/EmulatorLauncher.java 与
 * launcher/WinlatorPcLauncher.java；见 docs/LICENSE_NOTES.md 署名）：
 *  - PSP：ACTION_VIEW + 任意类型 MIME + 显式组件
 *    org.ppsspp.ppsspp/.PpssppActivity，授予 URI 读写权限。
 *  - PC：winlator-cn 导出入口 com.winlator/.ExternalLaunchActivity，
 *    extras：dir_path / exe_path / confirm / launch_id（可选覆盖：
 *    container_id / container_name / graphics_driver / dxwrapper /
 *    screen_size / lc_all）。无 SDK、无 AIDL、无回调。
 *  - 应用条目：getLaunchIntentForPackage（含 GameHub 导入的快捷方式）。
 */
object ExternalLaunchers {

    // ===== PSP（PPSSPP）=====

    /** PPSSPP 官方与改版的判定（改版包名通常含 ppsspp 字样）。 */
    fun isPpssppInstalled(context: Context): Boolean =
        try {
            context.packageManager.getPackageInfo("org.ppsspp.ppsspp", 0)
            true
        } catch (t: Throwable) {
            false
        }

    /** 启动 PSP 镜像。沙盒内路径自动转 content://（PPSSPP 是独立 UID，
     *  读不到本应用私有目录；content + GRANT 授权是标准解法，PPSSPP
     *  官方双 scheme 支持）。公共存储路径仍走 file://。 */
    fun launchPsp(context: Context, gamePath: String): String? {
        if (!isPpssppInstalled(context)) return "PPSSPP_NOT_INSTALLED"
        return try {
            val uri = LusicgalGamesProvider.toContentUri(context, gamePath)
                ?: if (gamePath.startsWith("/")) {
                    Uri.parse("file://$gamePath")
                } else {
                    Uri.parse(gamePath)
                }
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "*/*")
                setClassName("org.ppsspp.ppsspp", "org.ppsspp.ppsspp.PpssppActivity")
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
            context.startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "PPSSPP_ENTRY_MISSING"
        } catch (t: Throwable) {
            "LAUNCH_FAILED"
        }
    }

    // ===== PC（winlator-cn 外置启动协议）=====

    const val WINLATOR_PACKAGE = "com.winlator"
    const val WINLATOR_ENTRY = "com.winlator.ExternalLaunchActivity"

    const val EXTRA_DIR_PATH = "dir_path"
    const val EXTRA_EXE_PATH = "exe_path"
    const val EXTRA_CONFIRM = "confirm"
    const val EXTRA_LAUNCH_ID = "launch_id"
    const val EXTRA_CONTAINER_ID = "container_id"
    const val EXTRA_CONTAINER_NAME = "container_name"
    const val EXTRA_GRAPHICS_DRIVER = "graphics_driver"
    const val EXTRA_DXWRAPPER = "dxwrapper"
    const val EXTRA_SCREEN_SIZE = "screen_size"
    const val EXTRA_LC_ALL = "lc_all"

    fun isWinlatorInstalled(context: Context): Boolean =
        try {
            context.packageManager.getPackageInfo(WINLATOR_PACKAGE, 0)
            true
        } catch (t: Throwable) {
            false
        }

    fun isExternalLaunchSupported(context: Context): Boolean =
        try {
            context.packageManager.getActivityInfo(
                android.content.ComponentName(WINLATOR_PACKAGE, WINLATOR_ENTRY), 0
            )
            true
        } catch (t: Throwable) {
            false
        }

    /**
     * 启动 Windows 游戏。[overrides] 键与 winlator-cn extras 一致（空值不下发）。
     * 返回 null = 成功；否则为错误码（见 YukiHub 同协议定义）。
     *
     * 私有目录守卫：winlator-cn 按本机路径（dir_path）把目录挂进容器 ——
     * 它是独立 UID，Android 11+ FUSE 禁止跨应用访问 Android/data 与
     * /data/user —— 沙盒内目录必然挂载失败。这里提前给出
     * DIR_NOT_SHARED（用户可把游戏移到公共存储后原位重导）。
     */
    fun launchWinlator(
        context: Context,
        gameDir: String,
        exePath: String,
        launchId: String,
        overrides: Map<String, Any?>,
    ): String? {
        if (!isWinlatorInstalled(context)) return "PACKAGE_NOT_INSTALLED"
        if (!isExternalLaunchSupported(context)) return "EXTERNAL_LAUNCH_UNSUPPORTED"
        if (isUnderAppSandbox(context, gameDir)) return "DIR_NOT_SHARED"
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                setClassName(WINLATOR_PACKAGE, WINLATOR_ENTRY)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(EXTRA_DIR_PATH, gameDir)
                putExtra(EXTRA_EXE_PATH, exePath)
                putExtra(EXTRA_CONFIRM, false)
                putExtra(EXTRA_LAUNCH_ID, launchId)
                fun opt(name: String) {
                    val v = overrides[name]
                    if (v is String && v.isNotBlank()) putExtra(name, v)
                    if (v is Int && v != 0) putExtra(name, v)
                }
                opt(EXTRA_CONTAINER_ID)
                opt(EXTRA_CONTAINER_NAME)
                opt(EXTRA_GRAPHICS_DRIVER)
                opt(EXTRA_DXWRAPPER)
                opt(EXTRA_SCREEN_SIZE)
                opt(EXTRA_LC_ALL)
            }
            context.startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "ACTIVITY_NOT_FOUND"
        } catch (t: Throwable) {
            "LAUNCH_EXCEPTION"
        }
    }

    // ===== 应用条目（含 GameHub 快捷方式）=====

    /** [path] 是否在本应用私有沙盒内（Winlator 不可读区）。 */
    fun isUnderAppSandbox(context: Context, path: String): Boolean {
        if (path.isBlank() || !path.startsWith("/")) return false
        val target = try {
            java.io.File(path).canonicalPath
        } catch (t: Throwable) {
            return false
        }
        val roots = (listOf(context.filesDir) +
            context.getExternalFilesDirs(null).filterNotNull()).distinct()
        for (root in roots) {
            val rp = root.canonicalPath
            if (target == rp || target.startsWith(rp + java.io.File.separator)) return true
        }
        return false
    }

    /** 按包名启动（GameHub/Android 应用条目的通用形态）。 */
    fun launchAppEntry(context: Context, packageName: String, dataUri: String?): String? {
        return try {
            val intent = if (dataUri.isNullOrBlank()) {
                context.packageManager.getLaunchIntentForPackage(packageName)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(dataUri)).apply {
                    setPackage(packageName)
                }
            } ?: return "APP_NOT_LAUNCHABLE"
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            null
        } catch (t: Throwable) {
            "APP_NOT_INSTALLED"
        }
    }

    /** 可启动的应用清单（"添加应用条目"用；带图标由 UI 侧按需取）。 */
    fun listLaunchableApps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val me = context.packageName
        val out = ArrayList<Map<String, Any>>()
        // QUERY_ALL_PACKAGES 权限缺失时只能看到可交互应用 —— 对"游戏条目"
        // 场景恰好正确（只需可由启动器拉起的应用）。
        val own = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        for (ri in pm.queryIntentActivities(own, 0)) {
            if (ri.activityInfo.packageName == me) continue
            out.add(
                mapOf(
                    "package" to ri.activityInfo.packageName,
                    "label" to (ri.loadLabel(pm)?.toString() ?: ri.activityInfo.packageName),
                )
            )
        }
        out.sortBy { (it["label"] as String).lowercase() }
        return out
    }
}
