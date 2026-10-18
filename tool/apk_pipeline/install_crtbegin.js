'use strict';
// 重装：从 msys2 gcc 包里取 crtbegin.o/crtend.o 等启动对象放入 self-contained。
const fs = require('fs');
const path = require('path');
const { zstdDecompressSync } = require('zlib');

const TOOL = 'C:/LusicGal/.toolchain';
const SC = `${TOOL}/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained`;
const PKG = 'mingw-w64-ucrt-x86_64-gcc-16.2.0-6-any.pkg.tar.zst';

function untar(buf, dest) {
  let off = 0;
  const files = [];
  while (off + 512 <= buf.length) {
    const name = buf.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const sizeField = buf.toString('latin1', off + 124, off + 136).replace(/\0| /g, '');
    const size = sizeField ? parseInt(sizeField, 8) : 0;
    const target = path.join(dest, name);
    if (name.endsWith('/')) fs.mkdirSync(target, { recursive: true });
    else if (size > 0) {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, buf.subarray(off + 512, off + 512 + size));
      files.push(name);
    }
    off += 512 + Math.ceil(size / 512) * 512;
  }
  return files;
}

(async () => {
  const r = await fetch(`https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/${PKG}`);
  if (!r.ok) throw new Error(`fetch ${r.status}`);
  const files = untar(zstdDecompressSync(Buffer.from(await r.arrayBuffer())), `${TOOL}/gcc-pkg`);
  let n = 0;
  for (const f of files) {
    if (/crt(begin|end|endS|beginS)\.o$/.test(f)) {
      fs.copyFileSync(`${TOOL}/gcc-pkg/${f}`, path.join(SC, path.basename(f)));
      console.log('installed', path.basename(f));
      n++;
    }
  }
  console.log('total', n);
  fs.rmSync(`${TOOL}/gcc-pkg`, { recursive: true, force: true });
})();
