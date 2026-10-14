#!/usr/bin/env bash
# artemis 核心 Android arm64 构建：包装 scripts/build_rust_core.sh。
# 上游 art3m1s-core（Vulkan 后端 + ANativeWindow 外部表面）。
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/build_rust_core.sh" artemis
