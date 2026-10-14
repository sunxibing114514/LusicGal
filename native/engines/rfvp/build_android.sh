#!/usr/bin/env bash
# rfvp（FVP）核心 Android arm64 构建：包装 scripts/build_rust_core.sh。
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/build_rust_core.sh" rfvp
