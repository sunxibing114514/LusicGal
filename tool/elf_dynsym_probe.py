#!/usr/bin/env python3
"""ELF64 .dynsym 导出表抽查：确认 liblusicgal_*.so 真导出 lg_<id>_engine_*。

用法: python elf_dynsym_probe.py <apk> <符号前缀>
解包 lib/arm64-v8a/ 下匹配 liblusicgal_*.so 的库，逐个解析
Elf64_Shdr → .dynsym/.dynstr，列出以给定前缀命中的导出符号。
"""
import struct
import sys
import zipfile
import tempfile
import os

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass


def dynsyms(path):
    """返回 (全部动态符号名列表, 定义在该库中的符号名列表)。"""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        return None, None
    e_shoff = struct.unpack_from('<Q', data, 0x28)[0]
    e_shentsize = struct.unpack_from('<H', data, 0x3A)[0]
    e_shnum = struct.unpack_from('<H', data, 0x3C)[0]
    sections = []
    for i in range(e_shnum):
        sh = e_shoff + i * e_shentsize
        (sh_name, sh_type, sh_flags, sh_addr, sh_offset, sh_size,
         sh_link, sh_info, sh_addralign, sh_entsize) = struct.unpack_from(
            '<IIQQQQIIQQ', data, sh)
        sections.append(dict(name=sh_name, type=sh_type, offset=sh_offset,
                             size=sh_size, link=sh_link,
                             entsize=sh_entsize))
    out_all, out_defined = [], []
    for s in sections:
        if s['type'] != 11:  # SHT_DYNSYM
            continue
        strtab = sections[s['link']]
        for off in range(s['offset'], s['offset'] + s['size'], s['entsize']):
            if off + 24 > len(data):
                break
            st_name, st_info, st_other, st_shndx, st_value, st_size = \
                struct.unpack_from('<IBBHQQ', data, off)
            so = strtab['offset'] + st_name
            if so >= len(data):
                continue
            end = data.index(b'\x00', so)
            name = data[so:end].decode('utf-8', 'replace')
            if not name:
                continue
            out_all.append(name)
            if st_shndx != 0:  # SHN_UNDEF=0 → 本库未定义（导入）
                out_defined.append(name)
    return out_all, out_defined


def main(apk, prefix):
    z = zipfile.ZipFile(apk)
    libs = [n for n in z.namelist()
            if n.startswith('lib/arm64-v8a/liblusicgal_')
            and n.endswith('.so')]
    tmp = tempfile.mkdtemp(prefix='dynsym_', dir=os.path.dirname(apk))
    for n in sorted(libs):
        z.extract(n, tmp)
        path = os.path.join(tmp, n)
        _, defined = dynsyms(path)
        if defined is None:
            print(f'{os.path.basename(n)}: 非 ELF64，跳过')
            continue
        hits = [s for s in defined if s.startswith(prefix)]
        print(f'{os.path.basename(n)}: 导出 {len(defined)} 符号，{prefix}* 命中 {len(hits)}')
        for s in hits[:12]:
            print(f'    {s}')
    # 清理临时目录。
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
