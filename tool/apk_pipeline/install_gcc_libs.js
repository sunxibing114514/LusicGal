'use strict';
const fs = require('fs');
const path = require('path');
const { zstdDecompressSync } = require('zlib');

const TOOL = 'C:/LusicGal/.toolchain';
const SC = `${TOOL}/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained`;

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
  const tar = zstdDecompressSync(fs.readFileSync(`${TOOL}/ucrt64.db`));
  let off = 0, fname = null;
  while (off + 512 <= tar.length) {
    const name = tar.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const size = parseInt(tar.toString('latin1', off + 124, off + 136).replace(/\0| /g, ''), 8) || 0;
    // 精确找 gcc 主包（不带 -libs/-ada/-fortran 等后缀）
    if (name.endsWith('/desc') && /x86_64-gcc-\d/.test(name)) {
      const desc = tar.toString('utf8', off + 512, off + 512 + size);
      const nm = desc.match(/%NAME%\n([^\n]+)/);
      if (nm && nm[1].trim() === 'mingw-w64-ucrt-x86_64-gcc') {
        const m = desc.match(/%FILENAME%\n([^\n]+)/);
        if (m) fname = m[1].trim();
      }
    }
    off += 512 + Math.ceil(size / 512) * 512;
  }
  console.log('gcc pkg:', fname);
  if (!fname) process.exit(1);
  const r = await fetch(`https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/${fname}`);
  if (!r.ok) throw new Error(`fetch ${r.status}`);
  const zst = Buffer.from(await r.arrayBuffer());
  console.log('bytes', zst.length);
  const files = untar(zstdDecompressSync(zst), `${TOOL}/gcc-pkg`);
  let n = 0;
  for (const f of files) {
    if (/libgcc(_eh)?\.a$/.test(f)) {
      fs.copyFileSync(`${TOOL}/gcc-pkg/${f}`, path.join(SC, path.basename(f)));
      console.log('installed', path.basename(f), 'from', f);
      n++;
    }
  }
  console.log('total', n);
  fs.rmSync(`${TOOL}/gcc-pkg`, { recursive: true, force: true });
})();
