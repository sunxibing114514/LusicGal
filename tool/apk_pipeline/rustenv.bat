@echo off
REM LusicGal Rust 交叉编译环境（Windows GNU 宿主，免 VS/rustup）：
REM   rustc/cargo/std = 手动拼装的官方 dist 组件（GNU 宿主自带 rust-lld
REM   自足链接，proc-macro/build-script 可编）；目标 aarch64-linux-android
REM   链接器 = NDK r29 Windows 版 clang。
set "TOOL=C:\LusicGal\.toolchain"
set "RUST=%TOOL%\rust"
set "PATH=%RUST%\rustc\bin;%RUST%\cargo\bin;%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin;%PATH%"
set "RUSTC=%RUST%\rustc\bin\rustc.exe"
set "CARGO_HOME=%TOOL%\cargo-home"
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_AR=%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-ar.exe"
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=%TOOL%\android-ndk-r29\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android24-clang.cmd"
REM NDK r29 的 clang 包装器是 .cmd 而非 .bat —— cargo spawn 需要完整名。
set "CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS=-C link-arg=-landroid"
set "RUSTFLAGS=-C link-arg=-fPIC"
%*
