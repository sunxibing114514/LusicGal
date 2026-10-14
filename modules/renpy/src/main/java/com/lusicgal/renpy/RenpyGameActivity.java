package com.lusicgal.renpy;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;

import org.renpy.android.PythonSDLActivity;

/**
 * LusicGal 的 Ren'Py 外板壳 Activity（Route B）。
 *
 * librenpython.so（renpy-build 官方产物，SDL3 + Python 3.12 + ffmpeg 静态）
 * 不经 LusicGal ABI 桥 —— 由 rapt 的 PythonSDLActivity 生命周期承载，
 * 本类只注入游戏定位参数：
 *
 *   argv = [ <gamePath>, "--savedir", <savePath> ]
 *
 * 依据（renpy/renpy @ 80edccb 精读）：
 *  - renpy/bootstrap.py::bootstrap：`args.basedir`（位置参数）→
 *    `basedir = os.path.abspath(args.basedir)`，且 Android 下自动
 *    `os.mkdir(basedir + "/game")`；
 *  - renpy/loader.py::find_apks：`renpy_base != basedir` 时跳过
 *    `assets/x-game/` 的 APK 内读取 → 游戏完全走文件系统（我们的导入目录）；
 *  - renpy/arguments.py：`--savedir DIRECTORY` 官方支持 → LusicGal 的
 *    per-game 存档目录；
 *  - SDL3 SDLActivity.getArguments() → nativeRunMain 的 argv。
 *
 * 运行时资产（modules/renpy/build_android.sh 组装）：
 *  - jniLibs/arm64-v8a/librenpython.so
 *  - assets/private.mp3 = tar{ main.py + renpy/ Python 树（不含 common）}
 *    → 首跑经 PythonSDLActivity.unpackData("private") 解到 getFilesDir()
 *    （ANDROID_PRIVATE = renpy_base）
 *  - assets/x-renpy/x-common/** = renpy/common/**（逐段 x- 前缀，
 *    由 renpy loader 的 APK 类去前缀读回）
 */
public class RenpyGameActivity extends PythonSDLActivity {

    private static final String TAG = "LusicGalRenpy";

    public static final String EXTRA_GAME_ID = "lusicgal.game_id";
    public static final String EXTRA_GAME_PATH = "lusicgal.game_path";
    public static final String EXTRA_SAVE_PATH = "lusicgal.save_path";

    private String gameId = "";
    private String gamePath = null;
    private String savePath = null;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // 必须在 super.onCreate 之前取好 extras：SDL 主线程随后即读
        // getArguments() 并启动 librenpython。
        Intent intent = getIntent();
        if (intent != null) {
            gameId = intent.getStringExtra(EXTRA_GAME_ID);
            gamePath = intent.getStringExtra(EXTRA_GAME_PATH);
            savePath = intent.getStringExtra(EXTRA_SAVE_PATH);
            Log.i(TAG, "LusicGal renpy launch: game=" + gamePath
                    + " save=" + savePath);
        }
        super.onCreate(savedInstanceState);
    }

    /** SDL3 SDLActivity 钩子：传给 SDL_main 的 argv（见类注释）。 */
    @Override
    protected String[] getArguments() {
        if (gamePath == null) {
            Log.e(TAG, "无 lusicgal.game_path —— SDL_main 以缺省参数运行");
            return new String[0];
        }
        if (savePath == null) {
            return new String[]{gamePath};
        }
        return new String[]{gamePath, "--savedir", savePath};
    }
}
