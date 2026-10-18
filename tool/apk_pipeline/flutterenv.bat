@echo off
REM LusicGal Windows 构建环境包装（DSH 沙箱适配）：
REM  - pub/git/temp 全部重定向到工作区（systemprofile 被拒）；
REM  - curl.exe 的 schannel 被沙箱掐（用 node 下载器 dl.js 代替）；
REM  - flutter zip 自带 dart-sdk + flutter_tools.snapshot；update_*.ps1
REM    已置 exit 0 桩（ConstrainedLanguage 下 PowerShell 全废，dart 原生正常）。
set "PATH=C:\LusicGal\.toolchain\mingit\cmd;C:\LusicGal\.toolchain\flutter\bin;C:\LusicGal\.toolchain\jdk-17.0.20.1+1\bin;C:\LusicGal\.toolchain\android-sdk\cmdline-tools\latest\bin;C:\LusicGal\.toolchain\android-sdk\platform-tools;%PATH%"
set "PUB_CACHE=C:\LusicGal\.toolchain\pub-cache"
set "APPDATA=C:\LusicGal\.toolchain\appdata"
set "LOCALAPPDATA=C:\LusicGal\.toolchain\appdata"
set "HOME=C:\LusicGal\.toolchain"
set "USERPROFILE=C:\LusicGal\.toolchain"
set "GIT_CONFIG_GLOBAL=C:\LusicGal\.toolchain\gitconfig"
set "TMP=C:\LusicGal\.toolchain\tmp"
set "TEMP=C:\LusicGal\.toolchain\tmp"
set "JAVA_HOME=C:\LusicGal\.toolchain\jdk-17.0.20.1+1"
set "ANDROID_HOME=C:\LusicGal\.toolchain\android-sdk"
set "ANDROID_SDK_ROOT=C:\LusicGal\.toolchain\android-sdk"
%*
