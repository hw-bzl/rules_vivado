#!/usr/bin/env bash
# Test shim. See `vivado_2024_2.sh` for the PATH-restoration contract.
# 2025.1's install layout puts the version at the top level
# (`/tools/Xilinx/2025.1/Vivado/`) rather than nested under
# `/tools/Xilinx/Vivado/<ver>/` like earlier releases.
export PATH="/usr/local/bin:/tools/Xilinx/2025.1/Vivado/bin:${PATH:-/usr/bin:/bin}"
exec vivado "$@"
