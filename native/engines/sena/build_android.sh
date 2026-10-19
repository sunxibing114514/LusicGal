#!/usr/bin/env bash
# sena（SoftPAL）核心 Android arm64 构建：包装 scripts/build_rust_core.sh。
# 产出 liblusicgal_sena.so（sena-rs pal-vm CPU 帧缓冲 + lg_sena_* 壳）。
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/build_rust_core.sh" sena
