'use strict';
const fs = require('fs');
const path = require('path');
const SC = 'C:/LusicGal/.toolchain/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained';
for (const name of ['liblog.a', 'libm.a', 'libaaudio.a']) {
  const p = path.join(SC, name);
  if (!fs.existsSync(p)) { console.log(name, 'ABSENT'); continue; }
  const buf = fs.readFileSync(p);
  console.log(name, 'size', buf.length, 'armagic', buf.subarray(0, 8).toString('latin1').trim());
  // 第一个成员名 + 数据魔数
  const memName = buf.toString('latin1', 8, 8 + 16).trim();
  const data = buf.subarray(68, 68 + 4);
  console.log('  first member:', memName, 'magic:', data.toString('hex'));
}
// NDK sysroot 对照
const NDK = 'C:/LusicGal/.toolchain/android-ndk-r29/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/aarch64-linux-android';
for (const api of [24, 26]) {
  const p = `${NDK}/${api}/liblog.so`;
  console.log('NDK liblog api' + api, fs.existsSync(p) ? 'EXISTS' : 'missing');
  const p2 = `${NDK}/${api}/libaaudio.so`;
  console.log('NDK libaaudio api' + api, fs.existsSync(p2) ? 'EXISTS' : 'missing');
}
