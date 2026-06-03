# rules_vivado

[![BCR](https://img.shields.io/badge/BCR-rules_vivado-green?logo=bazel)](https://registry.bazel.build/modules/rules_vivado)
[![CI](https://github.com/hw-bzl/rules_vivado/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/hw-bzl/rules_vivado/actions/workflows/ci.yml)

Bazel rules for Xilinx Vivado FPGA synthesis, placement, routing, and
bitstream generation. HDL sources flow in through
[`rules_verilog`](https://registry.bazel.build/modules/rules_verilog)
(`VerilogInfo`) and
[`rules_vhdl`](https://registry.bazel.build/modules/rules_vhdl)
(`VhdlInfo`); the same `*_library` targets are reused for simulation
and synthesis.

The public surface is:

- **[`vivado_toolchain`](https://hw-bzl.github.io/rules_vivado/vivado_toolchain.html)** —
  wraps a shell script that sources your Vivado install. Mandatory:
  every `vivado_*` rule resolves it through Bazel toolchain
  resolution.
- **Per-phase rules** —
  [`vivado_project`](https://hw-bzl.github.io/rules_vivado/vivado_project.html) +
  [`vivado_synthesis`](https://hw-bzl.github.io/rules_vivado/vivado_synthesis.html),
  [`vivado_placement` / `vivado_routing`](https://hw-bzl.github.io/rules_vivado/vivado_implementation.html),
  [`vivado_bitstream`](https://hw-bzl.github.io/rules_vivado/vivado_bitstream.html),
  plus [IP composition](https://hw-bzl.github.io/rules_vivado/vivado_ip.html),
  [block designs](https://hw-bzl.github.io/rules_vivado/vivado_block_design.html)
  and [`vivado_xsim_test`](https://hw-bzl.github.io/rules_vivado/vivado_simulation.html).
  Each phase is its own target, composed explicitly: synthesis -> opt ->
  placement -> place-opt -> routing -> bitstream. See the
  [rule flow](https://hw-bzl.github.io/rules_vivado/flow.html) for how
  they connect.

Quick start, toolchain authoring, multi-version constraint gating, and
the full per-rule reference are hosted at
**<https://hw-bzl.github.io/rules_vivado/>**.

## License

Apache License 2.0
