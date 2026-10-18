#!/usr/bin/env node
// LusicGal Windows 管线：剥离 APK Signing Block v2/v3（还原未签名基座）。
// 结构（紧贴中央目录之前）：
//   [uint64 blockSize][pairs…][uint64 blockSize]["APK Sig Block 42"(16B)]
// CD 起点前 24 字节若命中 magic → 依 blockSize 摘除整块，EOCD 的 CD 偏移改指
// 新位置（数据区本地头偏移不受影响）。v1（META-INF/*）留给 apksigner 重签时覆盖。
// 用法：node strip_sigblock.js <in.apk> <out.apk>
'use strict';
const fs = require('fs');

const [,, inApk, outApk] = process.argv;
if (!inApk || !outApk) { console.error('用法: node strip_sigblock.js <in.apk> <out.apk>'); process.exit(2); }

const buf = fs.readFileSync(inApk);
let eocd = -1;
for (let i = buf.length - 22; i >= buf.length - 65558; i--) {
  if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
}
if (eocd < 0) throw new Error('EOCD not found');
const cdOff = buf.readUInt32LE(eocd + 16);

// magic 检查：CD 前第 25..8 字节（倒着 24..39）。
const magicOff = cdOff - 16;
if (buf.toString('latin1', magicOff, magicOff + 16) !== 'APK Sig Block 42') {
  console.log('无 v2/v3 签名块（CD 前非 magic）—— 原样输出');
  fs.copyFileSync(inApk, outApk);
  process.exit(0);
}
const size2 = Number(buf.readBigUInt64LE(cdOff - 24));   // 第二 size（含自身8B+magic16B）
const blockStart = cdOff - size2 - 8;                     // 第一 size 的位置
const size1 = Number(buf.readBigUInt64LE(blockStart));
if (size1 !== size2) throw new Error(`size1(${size1}) != size2(${size2})`);

// 新布局：[0..blockStart) + [cdOff..len)（CD+EOCD 平移），EOCD cd 偏移改 blockStart。
const tailLen = buf.length - cdOff;
const out = Buffer.allocUnsafe(blockStart + tailLen);
buf.copy(out, 0, 0, blockStart);
buf.copy(out, blockStart, cdOff, buf.length);
// EOCD 在新尾段中的位置：原 eocd - cdOff + blockStart。
const newEocd = eocd - cdOff + blockStart;
out.writeUInt32LE(blockStart, newEocd + 16);
fs.writeFileSync(outApk, out);
console.log(`✓ 剥离签名块 ${size1 + 8}B（[${blockStart}, ${cdOff})）→ ${outApk}`);
console.log('  下一步：add_libs / swap 后 zipalign + apksigner 重签');
