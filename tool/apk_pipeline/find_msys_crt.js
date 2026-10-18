'use strict';
const fs = require('fs');
(async () => {
  const url = 'https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/ucrt64.db';
  const r = await fetch(url);
  console.log('status', r.status, r.headers.get('content-length'));
  const buf = Buffer.from(await r.arrayBuffer());
  fs.writeFileSync('C:/LusicGal/.toolchain/ucrt64.db', buf);
  // pacman db = zstd 压缩的 tar：找 mingw-w64-crt-x86_64 的目录条目
  const { zstdDecompressSync } = require('zlib');
  const tar = zstdDecompressSync(buf);
  // 扫描 tar 头里的目录名
  let off = 0, found = [], sample = [];
  while (off + 512 <= tar.length) {
    const name = tar.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const size = parseInt(tar.toString('latin1', off + 124, off + 136).replace(/\0| /g, ''), 8) || 0;
    if (sample.length < 12) sample.push(name);
    if (/^mingw-w64-ucrt-x86_64-crt-\d/.test(name)) found.push(name.replace(/\/$/, ''));
    off += 512 + Math.ceil(size / 512) * 512;
  }
  console.log('--- sample:'); console.log(sample.join('\n'));
  console.log('--- crt:'); console.log(found.join('\n'));
})();
