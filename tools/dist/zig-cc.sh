#!/usr/bin/env bash
# Odin's linker (ODIN_CLANG_PATH) for the release: `zig cc` targeting an old
# glibc, so the game runs on distributions older than the build machine.
# Needs DIST_DIR (from build.sh dist): libX11.so and isoc23.o live there.
set -euo pipefail
GLIBC=2.29
args=()
for a in "$@"; do
	case "$a" in
		-l:/*) args+=("${a#-l:}") ;;   # zig wants static archives as plain paths
		-fuse-ld=*) ;;
		*) args+=("$a") ;;
	esac
done
exec zig cc -target "x86_64-linux-gnu.$GLIBC" -L"$DIST_DIR" "$DIST_DIR/isoc23.o" "${args[@]}"
