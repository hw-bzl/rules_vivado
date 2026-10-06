# rules_vivado

Bazel rules for Xilinx Vivado FPGA synthesis, placement, routing, and
bitstream generation.

## Overview

`rules_vivado` wires Xilinx Vivado into Bazel as a set of ordinary build
and test rules. HDL sources flow in through
[`rules_verilog`](https://registry.bazel.build/modules/rules_verilog)
(`VerilogInfo`) and
[`rules_vhdl`](https://registry.bazel.build/modules/rules_vhdl)
(`VhdlInfo`); the same `*_library` targets can be reused for simulation
and synthesis. The build phases are each their own rule
([`vivado_project`](./vivado_project.md) +
[`vivado_synthesis`](./vivado_synthesis.md),
[`vivado_placement`](./vivado_implementation.md),
[`vivado_routing`](./vivado_implementation.md),
[`vivado_bitstream`](./vivado_bitstream.md), …) so each phase's
checkpoint and reports are addressable as their own targets — build
`:my_synth` when you only want the synth `.dcp`, or `:my_bitstream`
for the end-to-end result.

The Xilinx install itself is resolved via a registered
[`vivado_toolchain`](./toolchains.md) — there is no per-target install
path to configure once a toolchain is in place.

## Quick start

The walkthrough below takes a Verilog top module from source to
bitstream by composing the per-phase rules directly — that's the
shape the ruleset is designed around.

### `MODULE.bazel`

```python
bazel_dep(name = "rules_verilog", version = "1.4.3")
bazel_dep(name = "rules_vhdl", version = "0.4.1")
bazel_dep(name = "rules_vivado", version = "{version}")

register_toolchains("//tools/vivado:vivado_toolchain")
```

A `vivado_toolchain` is **mandatory** — every `vivado_*` rule resolves
the Xilinx install through it. See [Toolchains](./toolchains.md) for
how to author one.

### `tools/vivado/vivado.sh`

```bash
#!/usr/bin/env bash
exec /opt/Xilinx/Vivado/2024.2/bin/vivado "$@"
```

Mark it executable: `chmod +x tools/vivado/vivado.sh`.

### `tools/vivado/BUILD.bazel`

```python
load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "vivado_local",
    vivado = "vivado.sh",
    env = {
        "XILINXD_LICENSE_FILE": "2100@license.example.com",
        "HOME": "/tmp",
    },
)

toolchain(
    name = "vivado_toolchain",
    toolchain = ":vivado_local",
    toolchain_type = "@rules_vivado//vivado:toolchain_type",
)
```

See [Toolchains](./toolchains.md) for license-server and multi-version
setup.

### `hello/hello.sv`

```systemverilog
module hello (
    input  wire clk,
    input  wire rst,
    output reg  led
);
  always_ff @(posedge clk) begin
    if (rst) led <= 1'b0;
    else     led <= ~led;
  end
endmodule
```

### `hello/BUILD.bazel`

```python
load("@rules_verilog//verilog:defs.bzl", "verilog_library")
load(
    "@rules_vivado//vivado:defs.bzl",
    "vivado_place_optimize",
    "vivado_placement",
    "vivado_project",
    "vivado_routing",
    "vivado_synthesis",
    "vivado_synthesis_optimize",
    "vivado_bitstream",
)

verilog_library(
    name = "hello",
    srcs = ["hello.sv"],
    data = ["hello.xdc"],
)

vivado_project(
    name = "hello_project",
    module = ":hello",
    module_top = "hello",
    part_number = "xc7a35ticsg324-1L",
)

vivado_synthesis(
    name = "hello_synth",
    project = ":hello_project",
)

vivado_synthesis_optimize(
    name = "hello_synth_opt",
    checkpoint = ":hello_synth",
)

vivado_placement(
    name = "hello_placement",
    checkpoint = ":hello_synth_opt",
)

vivado_place_optimize(
    name = "hello_place_opt",
    checkpoint = ":hello_placement",
)

vivado_routing(
    name = "hello_route",
    checkpoint = ":hello_place_opt",
)

vivado_bitstream(
    name = "hello_bitstream",
    checkpoint = ":hello_route",
)
```

### Build it

```text
$ bazel build //hello:hello_bitstream
$ ls bazel-bin/hello/
hello_bitstream.bit  hello_route.dcp  ...
```

Every intermediate target is buildable in isolation:

- `:hello_synth` — synthesis (`.dcp`)
- `:hello_synth_opt` — post-synthesis optimization
- `:hello_placement` — placement
- `:hello_place_opt` — post-placement optimization
- `:hello_route` — routing
- `:hello_bitstream` — final `.bit`

Build one directly to stop the flow early or to inspect the reports
that phase writes.

## Going further

- [Toolchains](./toolchains.md) — author a `vivado_toolchain`, register
  multiple versions, gate them with constraints and platforms.
- [Rules](./rules.md) — every public rule, indexed by build phase,
  with diagrams of how the rules and providers connect from HDL
  libraries through IP composition to bitstream and simulation.
