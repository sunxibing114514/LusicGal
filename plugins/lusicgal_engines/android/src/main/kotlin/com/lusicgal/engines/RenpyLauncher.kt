package com.lusicgal.engines

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build

/**
 * Ren'Py Route B 启动器（Android）：
 * renpy-build 的 librenpython.so 不经 LusicGal ABI 桥 —— 由独立"外板壳"
 * 模块（`com.lusicgal.renpy` / RenpyGameActivity，继承上游 PythonSDLActivity，
 * 以 drop-in 模块随包分发）承载完整游戏。
 *
 * 本类只负责：把 gamePath/savePath 传给该 Activity；未安装该模块时
 * 返回 CORE_NOT_BUNDLED（与其它核心缺库同语义）。
 *
 * 许可边界：librenpython.so 原样分发（LGPL-3.0 + Python 软件基金会许可，
 * renpy 自带 LICENSE 与源指针），不修改不静态并入 —— 见 docs/LICENSE_NOTES.md。
 */
object RenpyLauncher {
    private const val RENPY_ACTIVITY = "com.lusicgal.renpy.RenpyGameActivity"

    /** @return null=成功启动；否则给 Dart 的 errorCode。 */
    fun launch(context: Context, engineId: String, gameId: String,
               gamePath: String, savePath: String): String? {
        val intent = Intent().setClassName(context, RENPY_ACTIVITY).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("lusicgal.game_id", gameId)
            putExtra("lusicgal.game_path", gamePath)
            putExtra("lusicgal.save_path", savePath)
        }
        return try {
            if (context is Activity) {
                context.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            null
        } catch (e: Exception) {
            "CORE_NOT_BUNDLED"
        }
    }
}
