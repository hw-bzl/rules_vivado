#!/usr/bin/env bash
# Test shim. The toolchain's `vivado` attr tracks this file; `vivado_*`
# actions invoke it by absolute path.
#
# Bazel strips the action env down to what's declared on the toolchain,
# so PATH doesn't reach here — restore it with the standard container
# Vivado bin dir prepended. Falls through to whatever PATH the parent
# env already had, so a host with a different install works too as
# long as `vivado` ends up somewhere reachable.
#
# `/usr/local/bin` comes first because it holds the container's
# reproducibility wrapper (SOURCE_DATE_EPOCH, fakedate, Flexera
# LD_PRELOAD) that must win over the real binary. `/tools/Xilinx/
# Vivado/2024.2/bin` next so secondary tools (`xvlog`, `xelab`,
# `xsim`, `vitis_hls`, …) resolve without absolute paths.
export PATH="/usr/local/bin:/tools/Xilinx/Vivado/2024.2/bin:${PATH:-/usr/bin:/bin}"
exec vivado "$@"
