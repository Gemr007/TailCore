#!/bin/sh
# Собирает ядро в динамическую библиотеку для Linux/macOS:
# core/build/libtailcore.so или .dylib (+ заголовок libtailcore.h).
#
# Нужен рабочий cgo — на Linux gcc/clang, на macOS Xcode command line tools.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../core"
out="$core/build"
tags="$(tr -d '[:space:]' < "$here/build-tags.txt")"

case "$(uname -s)" in
  Darwin) ext=dylib ;;
  *)      ext=so ;;
esac

mkdir -p "$out"
cd "$core"
CGO_ENABLED=1 go build -tags "$tags" -buildmode=c-shared -o "$out/libtailcore.$ext" ./lib

ls -l "$out"
