#!/usr/bin/env bash
# Sourced by the xsim_test wrapper at `bazel test` runtime (before the
# exported `<top>.sh` driver runs) — the wrapper takes this file via
# the vivado_toolchain's `xilinx_env` attr.
#
# Bazel's docker sandbox strips PATH before invoking the wrapper, so
# the container's `ENV PATH=...` directives don't reach here. Restore
# a minimal PATH that puts `xvlog` / `xelab` / `xsim` (plus the rest
# of Vivado's per-version bin dir) in scope. Kept in sync with the
# corresponding shim (`vivado_2024_2.sh`).
export PATH="/usr/local/bin:/tools/Xilinx/Vivado/2024.2/bin:${PATH:-/usr/bin:/bin}"
