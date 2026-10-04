#!/usr/bin/env bash
# Build, run and test The Trial of Psyche.
#   ./build.sh            debug build and run
#   ./build.sh debug      debug build (bounds checks, leak report at exit)
#   ./build.sh release    optimised build
#   ./build.sh test       headless tests (rules, levels, i18n, settings, audio)
#   ./build.sh check FILE analyse a level file (reachability and illusions per view)
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
	*)       sed -n '2,8p' "$0"; exit 1 ;;
esac
