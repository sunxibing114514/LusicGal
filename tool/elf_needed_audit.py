#!/usr/bin/env python3
"""纯 Python ELF64 动态段审计：读出每个 .so 的 DT_NEEDED 全表。

用法: python elf_needed_audit.py <apk>
从 APK 提取 lib/arm64-v8a/*.so 后逐个解析动态段，输出每个库的
DT_NEEDED，并标记"包内缺失"的依赖（对照包内 lib 集合 + 系统库白名单）。
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

# Android 系统级 .so（bionic/NDK 运行时，不在 APK 里是正常的）。
SYSTEM_LIBS = {
    'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libandroid.so',
    'libGLESv1_CM.so', 'libGLESv2.so', 'libGLESv3.so', 'libEGL.so',
    'libOpenSLES.so', 'libaaudio.so', 'libvulkan.so', 'libnativewindow.so',
    'libmediandk.so', 'libbinder_ndk.so', 'libjnigraphics.so',
    'libandroid_net.so', 'libhardware.so', 'libbase.so', 'libutils.so',
    'libz.so', 'libstdc++.so', 'librt.so', 'libpthread.so',
}


def parse_needed(path):
    """解析 ELF64 little-endian 的 DT_NEEDED 列表。失败返回 None。"""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
        return None  # 非 ELF64 LE
    e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
    e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
    e_phnum = struct.unpack_from('<H', data, 0x38)[0]
    dyn_off = dyn_sz = None
    for i in range(e_phnum):
        ph = e_phoff + i * e_phentsize
        p_type = struct.unpack_from('<I', data, ph)[0]
        if p_type == 2:  # PT_DYNAMIC
            p_offset = struct.unpack_from('<Q', data, ph + 0x08)[0]
            p_filesz = struct.unpack_from('<Q', data, ph + 0x20)[0]
            dyn_off, dyn_sz = p_offset, p_filesz
            break
    if dyn_off is None:
        return []
    strtab = None
    needed = []
    pos = dyn_off
    end = dyn_off + dyn_sz
    while pos + 16 <= end:
        d_tag, d_val = struct.unpack_from('<QQ', data, pos)
        pos += 16
        if d_tag == 0:
            break
        if d_tag == 5:  # DT_STRTAB
            # PIE 共享库：d_val 是 vaddr；64 位 LE 下小文件里 vaddr
            # 常等于文件偏移（PT_LOAD 首段 0 起）。若不等则尽力映射。
            strtab = d_val
        elif d_tag == 1:  # DT_NEEDED
            needed.append(d_val)
    if strtab is None:
        return []
    out = []
    for off in needed:
        # 直接用 strtab 偏移读（绝大多数 Android .so 的 strtab vaddr ==
        # 文件偏移；不一致时尽力从所有 PT_LOAD 段映射一次）。
        o = off + strtab
        if o >= len(data):
            o = _map_vaddr(data, e_phoff, e_phnum, e_phentsize, strtab + off)
            if o is None:
                continue
        end_i = data.index(b'\x00', o)
        out.append(data[o:end_i].decode('utf-8', 'replace'))
    return out


def _map_vaddr(data, phoff, phnum, phentsize, vaddr):
    for i in range(phnum):
        ph = phoff + i * phentsize
        p_type = struct.unpack_from('<I', data, ph)[0]
        if p_type != 1:  # PT_LOAD
            continue
        p_vaddr = struct.unpack_from('<Q', data, ph + 0x10)[0]
        p_offset = struct.unpack_from('<Q', data, ph + 0x08)[0]
        p_filesz = struct.unpack_from('<Q', data, ph + 0x20)[0]
        if p_vaddr <= vaddr < p_vaddr + p_filesz:
            return p_offset + (vaddr - p_vaddr)
    return None


def main(apk_path):
    z = zipfile.ZipFile(apk_path)
    libs = [n for n in z.namelist()
            if n.startswith('lib/arm64-v8a/') and n.endswith('.so')]
    packaged = {os.path.basename(n) for n in libs}
    tmp = tempfile.mkdtemp(prefix='elfaudit_')
    for n in libs:
        z.extract(n, tmp)
    missing = {}
    for n in sorted(libs, key=lambda s: os.path.basename(s)):
        path = os.path.join(tmp, n)
        needs = parse_needed(path)
        if needs is None:
            print(f'{os.path.basename(n)}: （非 ELF64 或解析失败，跳过）')
            continue
        miss = [d for d in needs
                if d not in packaged and d not in SYSTEM_LIBS]
        print(f'{os.path.basename(n)}:')
        for d in needs:
            mark = '  ✗ 包内缺失' if d in miss else ''
            print(f'    {d}{mark}')
        if miss:
            missing[os.path.basename(n)] = miss
    print('\n===== 汇总：包内缺失的伴生依赖 =====')
    if not missing:
        print('（无）')
    for lib, miss in missing.items():
        for d in miss:
            print(f'{lib}  →  缺 {d}')


if __name__ == '__main__':
    main(sys.argv[1])
