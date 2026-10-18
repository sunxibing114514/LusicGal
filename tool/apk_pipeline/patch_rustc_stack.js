'use strict';
// 把 PE 头的 SizeOfStackReserve 提到 512MB（虚拟预留，不占实际内存），
// 让 rustc 主线程的深递归（巨型 crate 前端解析）不再爆栈。
// 用法：node patch_rustc_stack.js <rustc.exe 路径> [reserveMB=512]
const fs = require('fs');
const file = process.argv[2];
const reserveMB = parseInt(process.argv[3] || '512', 10);
if (!file) { console.error('need rustc.exe path'); process.exit(1); }
const buf = fs.readFileSync(file);
if (buf.readUInt16LE(0) !== 0x5a4d) { console.error('not MZ'); process.exit(1); }
const eLfanew = buf.readUInt32LE(0x3c);
if (buf.readUInt32LE(eLfanew) !== 0x4550) { console.error('not PE'); process.exit(1); }
const opt = eLfanew + 24; // COFF 20 字节 + PE 签名 4
const magic = buf.readUInt16LE(opt);
if (magic !== 0x20b) { console.error('not PE32+ (x64)'); process.exit(1); }
const offReserve = opt + 0x48;
const offCommit = opt + 0x50;
const oldReserve = buf.readBigUInt64LE(offReserve);
const oldCommit = buf.readBigUInt64LE(offCommit);
console.log('old reserve =', (Number(oldReserve) / 1048576).toFixed(0) + 'MB, commit =', (Number(oldCommit) / 1048576).toFixed(2) + 'MB');
buf.writeBigUInt64LE(BigInt(reserveMB) * 1048576n, offReserve);
buf.writeBigUInt64LE(64n * 1048576n, offCommit); // commit 64MB
fs.writeFileSync(file, buf);
console.log('new reserve =', reserveMB + 'MB (patched in place)');
