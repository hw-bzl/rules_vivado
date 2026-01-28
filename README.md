# rules_vivado

Bazel rules for Xilinx Vivado FPGA synthesis, placement, routing, and bitstream generation.

## Overview

`rules_vivado` provides Bazel rules to build FPGA designs using Xilinx Vivado. It integrates with `rules_verilator` to share the `VerilogInfo` provider, allowing the same Verilog/SystemVerilog libraries to be used for both simulation and synthesis.

## Setup

Add the following to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_verilator", version = "0.1.0")
bazel_dep(name = "rules_vivado", version = "0.1.0")
```

## Available Rules

### `verilog_library`

Define Verilog/SystemVerilog modules using `rules_verilator`:

```starlark
load("@rules_verilator//verilog:defs.bzl", "verilog_library")

verilog_library(
    name = "my_design",
    srcs = ["my_design.sv"],
    data = ["constraints.xdc"],
)
```

### `vivado_synthesize`

Synthesize a Verilog design:

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_synthesize")

vivado_synthesize(
    name = "my_design_synth",
    module = ":my_design",
    module_top = "my_design",
    part_number = "xczu28dr-ffvg1517-2-e",
    xilinx_env = ":xilinx_env.sh",
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
    xilinx_env = ":xilinx_env.sh",
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
    xilinx_env = ":xilinx_env.sh",
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
    xilinx_env = ":xilinx_env.sh",
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
    xilinx_env = ":xilinx_env.sh",
)
```

### `vivado_interface_definition`

Generate IP-XACT interface definition files (bus definition and abstraction definition XML) for custom interfaces:

```starlark
load("@rules_vivado//vivado:defs.bzl", "vivado_interface_definition")

vivado_interface_definition(
    name = "my_interface_def",
    interface_name = "my_interface",
    vendor = "mycompany.com",
    library = "interface",
    version = "1.0",
    signals = {
        "valid": ["direction_master=out", "direction_slave=in", "qualifier="],
        "ready": ["direction_master=in", "direction_slave=out", "qualifier="],
        "data": ["direction_master=out", "direction_slave=in", "qualifier=data", "width=32"],
        "addr": ["direction_master=out", "direction_slave=in", "qualifier=address", "width=16"],
    },
)
```

This generates:
- `my_interface.xml` - Bus definition XML
- `my_interface_rtl.xml` - Abstraction definition XML
- `my_interface_if_setup.tcl` - TCL setup file for IP packaging

Signal attributes:
- `direction_master`: Signal direction for master modport (`in` or `out`)
- `direction_slave`: Signal direction for slave modport (`in` or `out`)
- `qualifier`: Signal qualifier (`address`, `data`, `clock`, `reset`, or empty)
- `width`: Signal width (defaults to 1)
- `optional`: Whether the signal is optional (`true` or `false`, defaults to `false`)

## Xilinx Environment

All rules require a `xilinx_env.sh` script that sets up the Vivado environment:

```bash
#!/usr/bin/env bash
export HOME=/tmp
source /opt/xilinx/Vivado/2021.2/settings64.sh
export XILINXD_LICENSE_FILE=2100@localhost
```

## Providers

### From `rules_verilator`

- `VerilogInfo` - Verilog module information (sources, dependencies)

### From `rules_vivado`

- `VivadoSynthCheckpointInfo` - Synthesis checkpoint (.dcp)
- `VivadoPlacementCheckpointInfo` - Placement checkpoint
- `VivadoRoutingCheckpointInfo` - Routing checkpoint
- `VivadoIPBlockInfo` - IP block information
- `VivadoInterfaceInfo` - IP-XACT interface definition files

## License

Apache License 2.0
