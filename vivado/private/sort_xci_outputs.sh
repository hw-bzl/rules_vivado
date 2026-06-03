#!/bin/bash
# sort_xci_outputs.sh — split a `vivado_xci` IP tree into four
# per-language sibling TreeArtifacts.
#
# Usage:
#   sort_xci_outputs.sh \
#     --ip-dir <path>              # populated IP tree (input)
#     --verilog-dir <path>         # dest for .v / .sv / .vp / .svp
#     --verilog-header-dir <path>  # dest for .vh / .svh / .h
#     --vhdl-dir <path>            # dest for .vhd / .vhdl
#     --data-dir <path>            # dest for everything else
#
# Each file under <ip-dir> is copied into exactly one destination based
# on its extension. The file's path relative to <ip-dir> is preserved
# under the destination, so subtree structure (e.g. `sim/foo.v`,
# `hdl/foo_v1_0.v`) survives without name collisions across sibling dirs.
#
# Skipped subtrees — each would hand a `verilog_library`-shaped consumer a
# second definition of the IP's top module (or someone else's IP):
#   project/          scratch Vivado project, if a custom template leaves
#                     one behind (the stock template keeps it out of
#                     <ip-dir>)
#   *_imported_xci/   writable copies of upstream `ip_blocks`, which those
#                     targets already expose themselves
#   synth/            the synthesis wrapper. `sim/` carries the same module
#                     as a behavioural model usable by any simulator; the
#                     synth products reach Vivado flows through
#                     `vivado_project.ip_blocks` and the `.xci`, not through
#                     these dirs. Kept only when there is no `sim/` tree.

set -euo pipefail

ip_dir=""
verilog_dir=""
verilog_header_dir=""
vhdl_dir=""
data_dir=""

usage() {
    sed -n '2,17p' "$0" >&2
    exit "${1:-2}"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ip-dir)             ip_dir="$2"; shift 2 ;;
        --verilog-dir)        verilog_dir="$2"; shift 2 ;;
        --verilog-header-dir) verilog_header_dir="$2"; shift 2 ;;
        --vhdl-dir)           vhdl_dir="$2"; shift 2 ;;
        --data-dir)           data_dir="$2"; shift 2 ;;
        -h|--help)            usage 0 ;;
        *) echo "sort_xci_outputs.sh: unknown arg: $1" >&2; usage 2 ;;
    esac
done

for name in ip_dir verilog_dir verilog_header_dir vhdl_dir data_dir; do
    if [ -z "${!name}" ]; then
        echo "sort_xci_outputs.sh: --${name//_/-} is required" >&2
        exit 2
    fi
done

mkdir -p "$verilog_dir" "$verilog_header_dir" "$vhdl_dir" "$data_dir"

skip_synth=0
if [ -d "$ip_dir/sim" ]; then
    skip_synth=1
fi

while IFS= read -r -d '' src; do
    rel="${src#$ip_dir/}"
    case "$rel" in
        project/*|*_imported_xci/*) continue ;;
        synth/*) [ "$skip_synth" -eq 1 ] && continue ;;
    esac
    case "$rel" in
        *.v|*.sv|*.vp|*.svp) dest="$verilog_dir" ;;
        *.vh|*.svh|*.h)      dest="$verilog_header_dir" ;;
        *.vhd|*.vhdl)        dest="$vhdl_dir" ;;
        *)                   dest="$data_dir" ;;
    esac
    mkdir -p "$dest/$(dirname "$rel")"
    cp -f "$src" "$dest/$rel"
done < <(find "$ip_dir" -type f -print0)
