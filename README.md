# rules_vivado

[![BCR](https://img.shields.io/badge/BCR-rules_vivado-green?logo=bazel)](https://registry.bazel.build/modules/rules_vivado)
[![CI](https://github.com/hw-bzl/rules_vivado/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/hw-bzl/rules_vivado/actions/workflows/ci.yml)

Bazel rules for Xilinx Vivado FPGA synthesis, placement, routing, and bitstream generation.

## Overview

`rules_vivado` provides Bazel rules to build FPGA designs using Xilinx Vivado. HDL sources flow in through [`rules_verilog`](https://registry.bazel.build/modules/rules_verilog) (`VerilogInfo`) and [`rules_vhdl`](https://registry.bazel.build/modules/rules_vhdl) (`VhdlInfo`); the same libraries can be reused for simulation and synthesis.

## Setup

Add the following to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_verilog", version = "1.1.1")
bazel_dep(name = "rules_vhdl", version = "0.1.1")
bazel_dep(name = "rules_vivado", version = "0.2.0")
```

Then register at least one `vivado_toolchain` so every `vivado_*` rule can resolve the Xilinx environment script automatically — see [Toolchains](#toolchains) below.

## Toolchains

`rules_vivado` resolves the Xilinx environment via Bazel toolchain resolution. You declare a `vivado_toolchain` that wraps a shell script sourcing your Vivado install, wrap it in `toolchain(...)`, and register it from `MODULE.bazel`.

### Implementing a toolchain

1. Write a shell script that sources your Vivado install (and the license server, if applicable). The path convention is `tools/vivado/xilinx_env.sh` but anywhere works:

   ```bash
   #!/usr/bin/env bash
   set -e
   export HOME=/tmp
   source /opt/Xilinx/Vivado/2024.2/settings64.sh
   export XILINXD_LICENSE_FILE=2100@license.example.com
   ```

2. Declare a `vivado_toolchain` and a `toolchain()` wrapper in BUILD:

   ```starlark
   load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

   vivado_toolchain(
       name = "vivado_local",
       xilinx_env = "xilinx_env.sh",
   )

   toolchain(
       name = "vivado_toolchain",
       toolchain = ":vivado_local",
       toolchain_type = "@rules_vivado//vivado:toolchain_type",
   )
   ```

3. Register it from `MODULE.bazel`:

   ```starlark
   register_toolchains("//tools/vivado:vivado_toolchain")
   ```

That's it — every `vivado_*` rule now resolves this toolchain automatically; the per-rule `xilinx_env` attribute (deprecated) is no longer needed.

### Constraining toolchains

When you register multiple `vivado_toolchain` instances (one per Vivado version, one per docker image, …), gate each `toolchain()` on a `constraint_value` so Bazel picks the right one. `rules_vivado` exposes one `constraint_value` per known release in [`//vivado/constraints/BUILD.bazel`](vivado/constraints/BUILD.bazel) (auto-generated from [`//vivado/private:versions.bzl`](vivado/private/versions.bzl) `VIVADO_VERSIONS`).

```starlark
load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "vivado_2024_2",
    xilinx_env = "xilinx_env_2024_2.sh",
)

toolchain(
    name = "vivado_toolchain_2024_2",
    exec_compatible_with = ["@rules_vivado//vivado/constraints/version:2024.2"],
    toolchain = ":vivado_2024_2",
    toolchain_type = "@rules_vivado//vivado:toolchain_type",
)

platform(
    name = "vivado_2024_2_platform",
    constraint_values = ["@rules_vivado//vivado/constraints/version:2024.2"],
    exec_properties = {
        "container-image": "docker://your.registry/vivado:2024.2",
    },
    parents = ["@platforms//host"],
)
```

Register both from `MODULE.bazel`:

```starlark
register_toolchains("//tools/vivado:vivado_toolchain_2024_2")
register_execution_platforms("//tools/vivado:vivado_2024_2_platform")
```

The first registered exec platform is the default. Switch versions per build with `--platforms=//tools/vivado:vivado_2024_2_platform` — that also lets `target_compatible_with = ["@rules_vivado//vivado/constraints/version:2024.2"]` on a target evaluate against the right constraint (incompatible-at-default, compatible-when-platform-pinned). For per-target switching without a global flag, use a wrapper rule with `cfg = transition(...)` — see [`tests/transition.bzl`](tests/transition.bzl) for a `with_vivado_version` example that takes a list of targets and pins the version for the whole group.

Constraints are the only mechanism — there is no parallel build-setting / flag-driven path. This avoids the two-sources-of-truth problem and keeps the per-version metadata (constraints, `exec_properties` like `container-image`) all on the platform object where it belongs.

The same guidance lives in the [`//vivado:toolchain.bzl`](vivado/toolchain.bzl) module docstring for reference next to the rule itself.

## Available Rules

### `verilog_library`

Define Verilog/SystemVerilog modules using `rules_verilog`:

```starlark
load("@rules_verilog//verilog:defs.bzl", "verilog_library")

verilog_library(
    name = "my_design",
    srcs = ["my_design.sv"],
    data = ["constraints.xdc"],
)
```

### `vhdl_library`

Define VHDL modules using `rules_vhdl`:

```starlark
load("@rules_vhdl//vhdl:defs.bzl", "vhdl_library")

vhdl_library(
    name = "my_design",
    srcs = ["my_design.vhd"],
    library = "work",
    standard = "2008",
)
```

### `vivado_synthesize`

Synthesize a design (Verilog or VHDL):

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_synthesize")

vivado_synthesize(
    name = "my_design_synth",
    module = ":my_design",
    module_top = "my_design",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

### `vivado_flow`

Run the complete FPGA flow (synthesis, optimization, placement, routing, bitstream):

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_flow")

vivado_flow(
    name = "my_design_bitstream",
    module = ":my_design",
    module_top = "my_design",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

This creates intermediate targets:
- `my_design_bitstream_synth` - Synthesis
- `my_design_bitstream_synth_opt` - Synthesis optimization
- `my_design_bitstream_placement` - Placement
- `my_design_bitstream_place_opt` - Placement optimization
- `my_design_bitstream_route` - Routing
- `my_design_bitstream` - Final bitstream (.bit file)

### `vivado_create_project`

Create a Vivado project without running synthesis:

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_create_project")

vivado_create_project(
    name = "my_project",
    module = ":my_design",
    module_top = "my_design",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

### `vivado_create_ip`

Package a module as a Vivado IP core:

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_create_ip")

vivado_create_ip(
    name = "my_ip",
    module = ":my_design",
    module_top = "my_design",
    part_number = "xczu28dr-ffvg1517-2-e",
    ip_vendor = "my_company",
    ip_library = "my_lib",
    ip_version = "1.0",
)
```

### `xsim_test`

Run simulation tests using Vivado's XSim:

```starlark
load("@rules_vivado//vivado:defs.bzl", "xsim_test")

xsim_test(
    name = "my_design_xsim_test",
    module = ":my_testbench",
    module_top = "my_testbench",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

### `vivado_interface_definition`

Generate IP-XACT interface definition files (bus definition and abstraction definition XML) for custom SystemVerilog interfaces. This allows Vivado to recognize custom interfaces in block designs, enabling visual connection of IP blocks through typed interface ports.

The rule parses a SystemVerilog interface file to extract signal names, directions (from `modport` declarations), widths, and qualifiers (from `SPIRIT:` comments). It then generates the corresponding IP-XACT XML files and a TCL setup script.

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_interface_definition")

vivado_interface_definition(
    name = "my_interface_def",
    src = "my_interface.sv",
    interface_name = "my_interface",
    vendor = "mycompany.com",
    library = "interface",
    version = "1.0",
)
```

The SystemVerilog interface file uses `SPIRIT:` comments to annotate signals with IP-XACT qualifiers:

```systemverilog
interface my_interface #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 16
);
  // SPIRIT:ISADDRESS,REQUIRED
  logic [ADDR_WIDTH-1:0] addr;
  // SPIRIT:ISDATA,REQUIRED
  logic [DATA_WIDTH-1:0] data;
  // SPIRIT:REQUIRED
  logic                  valid;
  // SPIRIT:REQUIRED
  logic                  ready;
  // SPIRIT:OPTIONAL
  logic [15:0]           status;

  modport master(output addr, data, valid, input ready, status);
  modport slave(input addr, data, valid, output ready, status);
endinterface
```

Available `SPIRIT:` qualifiers:
- `ISADDRESS` - Signal carries address information
- `ISDATA` - Signal carries data
- `ISCLOCK` - Signal is a clock
- `ISRESET` - Signal is a reset
- `REQUIRED` - Signal must be connected
- `OPTIONAL` - Signal may be left unconnected

This generates:
- `my_interface.xml` - Bus definition XML
- `my_interface_rtl.xml` - Abstraction definition XML
- `my_interface_if_setup.tcl` - TCL setup file for IP packaging

To use the interface definition with other rules, attach it as `data` on a `verilog_library`:

```starlark
verilog_library(
    name = "my_interface",
    srcs = ["my_interface.sv"],
    data = [":my_interface_def"],
)
```

### `vivado_create_interface_ip`

Package a `vivado_interface_definition` as an IP catalog entry so Vivado can use the custom interface in block designs:

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_create_interface_ip")

vivado_create_interface_ip(
    name = "my_interface_ip",
    interface = ":my_interface_def",
    module = ":my_interface",
    part_number = "xczu28dr-ffvg1517-2-e",
)
```

IP blocks that use the custom interface should list the interface IP in their `ip_blocks` dependency:

```starlark
vivado_create_ip(
    name = "my_module_ip",
    ip_blocks = [":my_interface_ip"],
    module = ":my_module",
    module_top = "my_module",
    ...
)
```

See [`tests/`](tests/) for a complete example using custom BRAM read/write interfaces with a splitter module and block design project.

## Deprecated `xilinx_env` attribute

Each vivado-running rule still accepts a per-target `xilinx_env` attribute pointing at a shell script. **This attribute is deprecated** — if it is set, the rule prints a warning at analysis time directing you to register a `vivado_toolchain` instead. Migrate by dropping the attribute and registering a toolchain as described in [Toolchains](#toolchains).

## Providers

### From `rules_verilog`

- `VerilogInfo` - Verilog/SystemVerilog library information (sources, headers, data, transitive deps).

### From `rules_vhdl`

- `VhdlInfo` - VHDL library information (sources, library name, standard, transitive deps).

### From `rules_vivado`

- `VivadoToolchainInfo` - Resolved Xilinx environment.
- `VivadoSynthCheckpointInfo` - Synthesis checkpoint (.dcp)
- `VivadoPlacementCheckpointInfo` - Placement checkpoint
- `VivadoRoutingCheckpointInfo` - Routing checkpoint
- `VivadoIPBlockInfo` - IP block information
- `VivadoInterfaceInfo` - IP-XACT interface definition files

## License

Apache License 2.0
