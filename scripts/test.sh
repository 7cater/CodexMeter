#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/cache .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache" CoreChecks
