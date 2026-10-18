@echo off
REM LusicGal Rust cross-build env (Windows GNU host, no VS/rustup).
REM rustc/cargo/std assembled from official dist components. Host
REM (build scripts / proc-macros) links with rust-lld + mingw-w64
REM import libs (msys2 crt/winpthreads/gcc packages installed into
REM the rustlib self-contained dir). Target aarch64-linux-android
REM links with NDK r29 Windows clang wrapper. Cargo registry goes
REM through tool\apk_pipeline\lg_cargo_proxy.js (local plain-HTTP
REM bridge; schannel TLS is broken on this box).
set "TOOL=C:\LusicGal\.toolchain"
set "RUST=%TOOL%\rust"
set "RLD=%RUST%\rustc\lib\rustlib\x86_64-pc-windows-gnu\bin\rust-lld.exe"
set "PATH=%RUST%\rustc\bin;%RUST%\cargo\bin;%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin;%PATH%"
set "RUSTC=%RUST%\rustc\bin\rustc.exe"
set "CARGO_HOME=%TOOL%\cargo-home"
set "RUSTFLAGS=-C linker=%RLD% -C link-self-contained=yes"
set "CC_aarch64_linux_android=%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android24-clang.cmd"
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_AR=%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-ar.exe"
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android24-clang.cmd"
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS=-C link-arg=-landroid"
%*
