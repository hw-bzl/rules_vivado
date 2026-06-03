#!/usr/bin/env bash
# Sourced by the xsim_test wrapper at test runtime so `xvlog`, `xelab`,
# `xsim` resolve inside the docker sandbox. Build actions already find
# `vivado` via the container's default PATH, but the xsim driver
# (`simulate.sh`) invokes these tools by bare name and needs the
# Xilinx bin directory explicitly on PATH.
#
# For BCR analysis-only presubmit this file is never actually sourced —
# no tests run.
export PATH="/usr/local/bin:/tools/Xilinx/2025.1/Vivado/bin:${PATH:-/usr/bin:/bin}"
