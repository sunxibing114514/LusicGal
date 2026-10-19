#!/usr/bin/env bash
# siglus（KEY 系）核心 Android arm64 构建：包装 scripts/build_rust_core.sh。
set -euo pipefail
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../scripts" && pwd)/build_rust_core.sh" siglus
