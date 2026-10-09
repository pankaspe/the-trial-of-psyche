#!/usr/bin/env bash
# Build, run and test The Trial of Psyche.
#   ./build.sh            debug build and run
#   ./build.sh debug      debug build (bounds checks, leak report at exit)
#   ./build.sh release    optimised build
#   ./build.sh test       headless tests (rules, levels, i18n, settings, audio)
#   ./build.sh check FILE analyse a level file (reachability and illusions per view)
#   ./build.sh dist VER   Linux release archive (glibc 2.29+, needs zig): build/dist/
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
FLAGS=(-vet -strict-style)

case "${1:-run}" in
	debug)   odin build src -out:build/trial-of-psyche-debug -debug "${FLAGS[@]}" ;;
	release) odin build src -out:build/trial-of-psyche -o:speed "${FLAGS[@]}" ;;
	run)     odin build src -out:build/trial-of-psyche-debug -debug "${FLAGS[@]}" && ./build/trial-of-psyche-debug ;;
	test)    odin test tests "${FLAGS[@]}" -all-packages ;;
	check)   odin run tools/level_check -out:build/level_check "${FLAGS[@]}" -- "${2:?level file}" ;;
	dist)
		ver="${2:?version, e.g. 0.1.0}"
		name="the-trial-of-psyche-$ver-linux-x86_64"
		export DIST_DIR; DIST_DIR="$(mktemp -d)"   # Odin can't spawn a linker path with spaces
		rm -rf "build/dist/$name"
		mkdir -p "build/dist/$name"
		cp tools/dist/zig-cc.sh "$DIST_DIR/"
		ln -s "$(ldconfig -p | grep -m1 -o '/[^ ]*/libX11\.so\.6$')" "$DIST_DIR/libX11.so"
		zig cc -target x86_64-linux-gnu.2.29 -O2 -c tools/dist/isoc23.c -o "$DIST_DIR/isoc23.o"
		ODIN_CLANG_PATH="$DIST_DIR/zig-cc.sh" \
			odin build src -out:"build/dist/$name/trial-of-psyche" -o:speed "${FLAGS[@]}"
		cp LICENSE tools/dist/README.txt "build/dist/$name/"
		cp assets/fonts/OFL-*.txt "build/dist/$name/"
		tar -C build/dist -czf "build/dist/$name.tar.gz" "$name"
		rm -rf "$DIST_DIR"
		echo "build/dist/$name.tar.gz"
		;;
	*)       sed -n '2,9p' "$0"; exit 1 ;;
esac
