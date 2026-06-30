#!/usr/bin/env bash
# Test shim. The toolchain's `vivado` attr tracks this file; `vivado_*`
# actions invoke it by absolute path. Sourcing `settings64.sh` is left to
# this shim (it sets `XILINX_VIVADO`, `LD_LIBRARY_PATH`, etc. — things
# `env` can't compose cleanly). Static env (`XILINXD_LICENSE_FILE`,
# `HOME`) is set on the toolchain's `env` dict in BUILD.
source /opt/xilinx/2021.2/Vivado/settings64.sh
exec vivado "$@"
