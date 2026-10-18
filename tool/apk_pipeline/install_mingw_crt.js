'use strict';
// 下载 msys2 的 mingw-w64-crt-x86_64 包（全套 Windows 导入库），把
// x86_64-w64-mingw32/lib/*.a 与 crt 对象铺进 Rust 的 self-contained 目录，
// 并用 llvm-ar 造空的 libgcc/libgcc_eh 存根（rustc 链接行里的 -lgcc/-lgcc_eh
// 由 Rust 自带的 compiler_builtins/libunwind 满足，存根仅作占位）。
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { zstdDecompressSync } = require('zlib');

const PKG = 'mingw-w64-ucrt-x86_64-crt-14.0.0.r495.g63ebe6cdb-1-any.pkg.tar.zst';
const URL = `https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/ucrt64/${PKG}`;
const TOOL = 'C:/LusicGal/.toolchain';
const SC = `${TOOL}/rust/rustc/lib/rustlib/x86_64-pc-windows-gnu/lib/self-contained`;
const AR = `${TOOL}/android-ndk-r29/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-ar.exe`;

function untar(buf, dest) {
  let off = 0;
  const files = [];
  while (off + 512 <= buf.length) {
    const name = buf.toString('latin1', off, off + 100).replace(/\0/g, '');
    if (!name) break;
    const sizeField = buf.toString('latin1', off + 124, off + 136).replace(/\0| /g, '');
    const size = sizeField ? parseInt(sizeField, 8) : 0;
    const type = buf[off + 156];
    const target = path.join(dest, name);
    if (type === 53 || name.endsWith('/')) { // '5' = dir
      fs.mkdirSync(target, { recursive: true });
    } else if (size > 0) {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, buf.subarray(off + 512, off + 512 + size));
      files.push(name);
    }
    off += 512 + Math.ceil(size / 512) * 512;
  }
  return files;
}

(async () => {
  const r = await fetch(URL);
  if (!r.ok) throw new Error(`fetch ${r.status}`);
  const zst = Buffer.from(await r.arrayBuffer());
  console.log('pkg bytes', zst.length);
  const tar = zstdDecompressSync(zst);
  const files = untar(tar, `${TOOL}/crt-pkg`);
  const libs = files.filter(f => /\/lib\/[^/]+\.a$/.test(f) || /crt2?\.o$/.test(f));
  let copied = 0;
  for (const f of libs) {
    const base = path.basename(f);
    if (f.includes('/lib/')) {
      fs.copyFileSync(`${TOOL}/crt-pkg/${f}`, path.join(SC, base));
      copied++;
    }
  }
  console.log('copied .a into self-contained:', copied);
  // 空 libgcc 存根（无成员归档）
  for (const stub of ['libgcc.a', 'libgcc_eh.a']) {
    const p = path.join(SC, stub);
    if (!fs.existsSync(p)) {
      const empty = path.join(TOOL, 'empty.o');
      fs.writeFileSync(empty, Buffer.alloc(0));
      try {
        execFileSync(AR, ['rcs', p, empty]);
      } catch {
        // llvm-ar 拒绝空对象时用纯归档头
        const hdr = Buffer.alloc(8 + 60 + 1 + 20 + 1);
        hdr.write('!<arch>\n', 0, 'latin1');
        hdr.write('stub.o/           0           0     0     644     0         `\n', 8, 'latin1');
        fs.writeFileSync(p, hdr.subarray(0, 8 + 61));
      }
      fs.rmSync(empty, { force: true });
    }
  }
  console.log('libgcc stubs done');
  fs.rmSync(`${TOOL}/crt-pkg`, { recursive: true, force: true });
  console.log('crt-pkg cleaned');
})();
