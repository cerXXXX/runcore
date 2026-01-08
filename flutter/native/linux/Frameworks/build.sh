#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/go.mod" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(cd "$dir/.." && pwd)"
  done
  return 1
}

ROOT="$(find_repo_root)" || { echo "go.mod not found; run from inside the repo" >&2; exit 1; }
OUTROOT="$SCRIPT_DIR"

export GOCACHE="${GOCACHE:-$ROOT/.gocache}"
mkdir -p "$GOCACHE"

header_src() {
  if [ -f "$ROOT/flutter/native/apple/Frameworks/iOS/runcore.h" ]; then
    echo "$ROOT/flutter/native/apple/Frameworks/iOS/runcore.h"
  elif [ -f "$ROOT/flutter/native/apple/Frameworks/macOS/runcore.h" ]; then
    echo "$ROOT/flutter/native/apple/Frameworks/macOS/runcore.h"
  elif [ -f "$ROOT/apple/Frameworks/iOS/runcore.h" ]; then
    echo "$ROOT/apple/Frameworks/iOS/runcore.h"
  elif [ -f "$ROOT/apple/Frameworks/macOS/runcore.h" ]; then
    echo "$ROOT/apple/Frameworks/macOS/runcore.h"
  else
    echo ""
  fi
}

build_linux() {
  local hs goarch out
  hs="$(header_src)"
  if [ -z "$hs" ]; then
    echo "runcore.h not found (expected under flutter/native/apple/Frameworks)" >&2
    exit 1
  fi

  goarch="$(go env GOARCH)"
  out="$OUTROOT/linux/$goarch"
  mkdir -p "$out"
  cp "$hs" "$out/runcore.h"

  echo "Building Linux ($goarch) libruncore.so..."
  (
    cd "$ROOT"
    export CGO_ENABLED=1
    export GOOS=linux
    export GOARCH="$goarch"
    go build -buildmode=c-shared -o "$out/libruncore.so" ./ffi/runcorec
  )

  echo "OK: $out/libruncore.so"
}

cmd="${1:-linux}"
case "$cmd" in
  linux)
    build_linux
    ;;
  *)
    echo "Usage: $0 {linux}" >&2
    exit 2
    ;;
esac

