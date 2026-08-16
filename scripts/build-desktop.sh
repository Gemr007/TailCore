#!/bin/sh
# Собирает ядро в динамическую библиотеку для Linux/macOS:
# core/build/libtalecore.so или .dylib (+ заголовок libtalecore.h).
#
# Нужен рабочий cgo — на Linux gcc/clang, на macOS Xcode command line tools.
set -eu

core="$(cd "$(dirname "$0")/../core" && pwd)"
out="$core/build"

case "$(uname -s)" in
  Darwin) ext=dylib ;;
  *)      ext=so ;;
esac

mkdir -p "$out"
cd "$core"
CGO_ENABLED=1 go build -tags with_utls -buildmode=c-shared -o "$out/libtalecore.$ext" ./lib

ls -l "$out"
