#!/bin/sh
# sanitize_paths.sh <sandbox_root> <marker> <path> [<path> ...]
#
# Rewrites every occurrence of `<sandbox_root>/` -> `<marker>` inside
# each declared output so Vivado artifacts are byte-identical across
# hosts, sandbox strategies, and RBE-worker sandbox UUIDs. Paths that
# name a TreeArtifact directory are walked recursively. Binary formats
# where sed would corrupt the file are skipped.
#
# This applies to EVERY declared output, TreeArtifacts included — most
# visibly `vivado_export_simulation`, whose tree is a bundle of generated
# `compile.sh` / `elaborate.sh` / `simulate.sh` scripts full of absolute
# paths. Rewriting those to `<execroot>/` means the exported bundle is
# not directly runnable from the output tree, and that is deliberate:
# leaving the sandbox root in would bake a per-invocation, per-worker
# path into a cacheable artifact, so the first machine to populate the
# cache would hand every later consumer paths that don't exist for them.
# Consumers that need to run the bundle re-point the marker at their own
# root (`sed -i "s|<execroot>/|$PWD/|g"`) as a setup step.
#
# POSIX sh — no bashisms (no `local`, no `pipefail`, no `[[`).

set -eu

sandbox_root="$1"
shift
marker="$1"
shift

# `find` accepts a plain file just as happily as a directory (it visits
# exactly that file when `-type f` matches), so one call covers both
# single-file and TreeArtifact outputs — the skip-list lives in one place.
for target in "$@"; do
    find "$target" -type f \
        ! -name '*.dcp' \
        ! -name '*.pdi' \
        ! -name '*.bit' \
        ! -name '*.xsa' \
        ! -name '*.ltx' \
        ! -name '*.wdb' \
        ! -name '*.wcfg' \
        -exec sed -i "s|${sandbox_root}/|${marker}|g" {} + 2>/dev/null || true
done
