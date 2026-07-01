#!/usr/bin/env bash
# Example shim. In a real consumer this hard-codes the install path of
# `vivado` inside your container image, e.g.:
#   exec /opt/Xilinx/Vivado/2024.2/bin/vivado "$@"
# For BCR analysis-only presubmit we just defer to PATH.
exec vivado "$@"
