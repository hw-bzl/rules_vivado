#!/usr/bin/env bash
# Test shim. See `vivado_2024_1.sh` for the contract.
source /opt/xilinx/2025.1/Vivado/settings64.sh
exec vivado "$@"
