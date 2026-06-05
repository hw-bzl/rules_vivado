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
([`vivado_synthesize`](./vivado_synthesis.md),
[`vivado_placement`](./vivado_implementation.md),
[`vivado_routing`](./vivado_implementation.md),
[`vivado_write_bitstream`](./vivado_bitstream.md), …) so checkpoints are
cached between phases, or you can chain the whole flow with the
`vivado_flow` macro.

The Xilinx install itself is resolved via a registered
[`vivado_toolchain`](./toolchains.md) — there is no per-target install
path to configure once a toolchain is in place.

## Quick start

The walkthrough below takes a Verilog top module from source to
bitstream with the `vivado_flow` macro.

### `MODULE.bazel`

```python
bazel_dep(name = "rules_verilog", version = "1.1.1")
bazel_dep(name = "rules_vhdl", version = "0.1.1")
bazel_dep(name = "rules_vivado", version = "{version}")

register_toolchains("//tools/vivado:vivado_toolchain")
```

A `vivado_toolchain` is **mandatory** — every `vivado_*` rule resolves
the Xilinx install through it. See [Toolchains](./toolchains.md) for
how to author one.

### `tools/vivado/BUILD.bazel`

```python
load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "vivado_local",
    env = {
        "XILINX_VIVADO": "/opt/Xilinx/Vivado/2024.2",
        "PATH": "/opt/Xilinx/Vivado/2024.2/bin:/usr/bin:/bin",
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

See [Toolchains](./toolchains.md) for license-server, multi-version,
and shell-hook setup.

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
load("@rules_vivado//vivado:defs.bzl", "vivado_flow")

verilog_library(
    name = "hello",
    srcs = ["hello.sv"],
    data = ["hello.xdc"],
)

vivado_flow(
    name = "hello_bitstream",
    module = ":hello",
    module_top = "hello",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

### Build it

```text
$ bazel build //hello:hello_bitstream
$ ls bazel-bin/hello/
hello_bitstream.bit  hello_bitstream_route.dcp  ...
```

`vivado_flow` is a convenience macro — it expands to the per-phase
rules below so each checkpoint is cached on its own:

- `hello_bitstream_synth` — synthesis (`.dcp`)
- `hello_bitstream_synth_opt` — post-synthesis optimization
- `hello_bitstream_placement` — placement
- `hello_bitstream_place_opt` — post-placement optimization
- `hello_bitstream_route` — routing
- `hello_bitstream` — final `.bit`

Build any one of them directly to stop the flow early or to inspect
intermediate reports.

## Going further

- [Toolchains](./toolchains.md) — author a `vivado_toolchain`, register
  multiple versions, gate them with constraints and platforms.
- [Rules](./rules.md) — every public rule, indexed by build phase.
