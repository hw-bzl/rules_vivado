# Rules

Every public rule in `rules_vivado`, grouped by the build phase it
belongs to, with diagrams of how each group connects. All of them
resolve their Xilinx install through a registered
[`vivado_toolchain`](./toolchains.md); that edge is left out of the
diagrams because it reaches every node.

In the diagrams, each box is a rule and each arrow is a Bazel
dependency, labelled with the attribute on the consuming rule and the
provider that crosses it. Boxes outside the dashed groups come from
other rulesets.

## End to end

```mermaid
flowchart LR
    subgraph hdl [HDL and constraints]
        VL["verilog_library<br/>vhdl_library"]
        XL[xdc_library]
        TB[tcl_binary]
    end

    subgraph ip [IP composition]
        XCI[vivado_xci]
        IPC[vivado_ip_core]
        IFD[vivado_interface_definition]
        IFIP[vivado_interface_ip]
        PIP[vivado_packaged_ip]
        BD[vivado_block_design]
    end

    PRJ[vivado_project]

    subgraph impl [Synthesis and implementation]
        SYN[vivado_synthesis]
        SOPT[vivado_synthesis_optimize]
        PLC[vivado_placement]
        POPT[vivado_place_optimize]
        RTE[vivado_routing]
    end

    subgraph out [Hand-off artifacts]
        BIT["vivado_bitstream<br/>.bit"]
        PDI["vivado_device_image<br/>.pdi"]
        XSA["vivado_hw_platform<br/>.xsa"]
        LTX["vivado_debug_probes<br/>.ltx"]
    end

    subgraph sim [Simulation and export]
        XSIM[vivado_xsim_test]
        EXS[vivado_export_simulation]
        PEX[vivado_project_export]
        SIMLIB[vivado_compile_simlib]
    end

    VL -- "module<br/>VerilogInfo / VhdlInfo" --> PRJ
    VL -- "module" --> IPC
    VL -- "hdl_libraries" --> PIP
    XL -- "data<br/>XdcInfo" --> PRJ
    TB -- "script<br/>pre_hooks / post_hooks" --> BD
    TB -- "script" --> XCI

    IFD -- "interface<br/>VivadoInterfaceInfo" --> IFIP
    XCI -- "ip_blocks<br/>VivadoIPBlockInfo" --> BD
    IPC -- "ip_blocks" --> BD
    IFIP -- "ip_blocks" --> BD
    PIP -- "ip_blocks" --> BD
    XCI -- "ip_blocks" --> PRJ
    IPC -- "ip_blocks" --> PRJ
    PIP -- "ip_blocks" --> PRJ
    BD -- "block_designs<br/>VivadoBlockDesignInfo" --> PRJ

    PRJ -- "project<br/>VivadoProjectInfo" --> SYN
    PRJ -- "project" --> XSIM
    PRJ -- "project" --> EXS
    PRJ -- "project" --> PEX

    SYN -- "checkpoint<br/>VivadoSynthCheckpointInfo" --> SOPT
    SOPT -- "checkpoint" --> PLC
    PLC -- "checkpoint<br/>VivadoPlacementCheckpointInfo" --> POPT
    POPT -- "checkpoint" --> RTE
    RTE -- "checkpoint<br/>VivadoRoutingCheckpointInfo" --> BIT
    RTE -- "checkpoint" --> PDI
    RTE -- "checkpoint" --> XSA
    RTE -- "checkpoint" --> LTX
```

`vivado_compile_simlib` stands alone: it pre-compiles the Xilinx
simulation libraries for a third-party simulator and hands the result to
whatever consumes a `vivado_export_simulation` bundle, outside this
ruleset.

## Project setup

- [`vivado_project`](./vivado_project.md) — emit a TCL script that
  creates a Vivado project (no Vivado invocation at build time).
  Consumed by `vivado_synthesis`, the simulation rules,
  `vivado_project_export`, and GUI launchers.
- [`xdc_library`](./vivado_xdc_library.md) — bundle constraint files
  with the constraint files they must run after; drops into
  `vivado_project.data`.
- [`vivado_project_export`](./vivado_project_export.md) — open the
  project, source a user `tcl_binary`, and capture the files it writes.

## Project to bitstream

The implementation chain is one rule per Vivado command, and each rule
accepts the provider of the phase before it. The two optimization phases
are optional: `vivado_placement` takes a `VivadoSynthCheckpointInfo`
from either `vivado_synthesis` or `vivado_synthesis_optimize`, and
`vivado_routing` takes a `VivadoPlacementCheckpointInfo` from either
`vivado_placement` or `vivado_place_optimize`.

### Synthesis

- [`vivado_synthesis`](./vivado_synthesis.md) — run synthesis on a
  `vivado_project` and produce a synthesis checkpoint (`.dcp`).
- [`vivado_synthesis_optimize`](./vivado_synthesis.md) — post-synthesis
  optimization pass on a synthesis checkpoint.

### Implementation

- [`vivado_placement`](./vivado_implementation.md) — placement on a
  synthesis checkpoint.
- [`vivado_place_optimize`](./vivado_implementation.md) —
  post-placement optimization on a placement checkpoint.
- [`vivado_routing`](./vivado_implementation.md) — routing on a
  placement checkpoint.

### Hand-off artifacts

- [`vivado_bitstream`](./vivado_bitstream.md) — emit the final `.bit`
  from a routing checkpoint.
- [`vivado_device_image`](./vivado_bitstream.md) — emit a Versal `.pdi`
  from a routing checkpoint.
- [`vivado_hw_platform`](./vivado_hw_platform.md) — emit the `.xsa`
  hardware platform for Vitis / PetaLinux from a routing checkpoint.
- [`vivado_debug_probes`](./vivado_debug_probes.md) — emit the `.ltx`
  probe file for Hardware Manager from any phase checkpoint.

### How the chain connects

```mermaid
flowchart TD
    PRJ["vivado_project<br/><i>emits .project.tcl, runs no Vivado</i>"]
    SYN["vivado_synthesis<br/><i>synth_design, .dcp + impl-XDC bundle</i>"]
    SOPT["vivado_synthesis_optimize<br/><i>opt_design</i>"]
    PLC["vivado_placement<br/><i>place_design</i>"]
    POPT["vivado_place_optimize<br/><i>phys_opt_design</i>"]
    RTE["vivado_routing<br/><i>route_design</i>"]
    BIT["vivado_bitstream<br/><i>write_bitstream</i>"]
    PDI["vivado_device_image<br/><i>write_device_image (Versal)</i>"]
    XSA["vivado_hw_platform<br/><i>write_hw_platform</i>"]
    LTX["vivado_debug_probes<br/><i>write_debug_probes</i>"]

    PRJ -- VivadoProjectInfo --> SYN
    SYN -- VivadoSynthCheckpointInfo --> SOPT
    SYN -. "optional phase skipped" .-> PLC
    SOPT -- VivadoSynthCheckpointInfo --> PLC
    PLC -- VivadoPlacementCheckpointInfo --> POPT
    PLC -. "optional phase skipped" .-> RTE
    POPT -- VivadoPlacementCheckpointInfo --> RTE
    RTE -- VivadoRoutingCheckpointInfo --> BIT
    RTE -- VivadoRoutingCheckpointInfo --> PDI
    RTE -- VivadoRoutingCheckpointInfo --> XSA
    SYN -. "any checkpoint provider" .-> LTX
    PLC -. "any checkpoint provider" .-> LTX
    RTE -- VivadoRoutingCheckpointInfo --> LTX
```

Two providers ride along the whole chain rather than crossing a single
edge:

- `VivadoLogInfo` accumulates every upstream phase's `.log` and `.jou`,
  so building `:my_bitstream` with `--output_groups=log` yields the logs
  of synthesis through bitstream.
- `VivadoReportsInfo` maps each phase's `reports` attr to its declared
  report files.

Every phase rule also carries `pre_hooks` and `post_hooks`: `.tcl`,
`.xdc`, `.sdc` files or `tcl_binary` targets sourced inside the Vivado
session before and after the phase's main command.

## IP composition

IP enters a project in two shapes. `VivadoIPBlockInfo` describes a repo
plus, optionally, a configured `.xci` or a VLNV to `create_ip`;
`VivadoBlockDesignInfo` describes a `.bd` and the IP repos it needs.

- [`vivado_xci`](./vivado_ip.md) — configure a Xilinx-catalog IP from a
  `tcl_binary` script into a consumable IP repo. Besides
  `VivadoIPBlockInfo` it exposes `VerilogInfo` and `VhdlInfo`, so it
  can also sit in a `verilog_library`'s `deps` (dashed edge below).
- [`vivado_ip_core`](./vivado_ip.md) — package your own HDL module as a
  reusable Vivado IP core.
- [`vivado_interface_definition`](./vivado_ip.md) — turn a
  SystemVerilog `interface` into IP-XACT bus and abstraction
  definitions.
- [`vivado_interface_ip`](./vivado_ip.md) — register an interface
  definition as an IP catalog entry so block designs can connect to it.
- [`vivado_packaged_ip`](./vivado_packaged_ip.md) — stage an
  already-packaged IP repo for `ip_blocks`.
- [`vivado_block_design`](./vivado_block_design.md) — build a `.bd` from
  a `tcl_binary` script for `vivado_project.block_designs`, forwarding
  the IP repos its cells reference.

```mermaid
flowchart LR
    SV["SystemVerilog<br/>interface .sv"]
    IFD[vivado_interface_definition]
    IFIP[vivado_interface_ip]
    VL["verilog_library<br/>vhdl_library"]
    IPC[vivado_ip_core]
    XCI[vivado_xci]
    PIP[vivado_packaged_ip]
    BD[vivado_block_design]
    PRJ[vivado_project]

    SV -- src --> IFD
    IFD -- "interface<br/>VivadoInterfaceInfo" --> IFIP
    VL -- module --> IPC
    VL -- hdl_libraries --> PIP
    IFIP -- "ip_blocks<br/>VivadoIPBlockInfo" --> IPC
    XCI -- "ip_blocks" --> IPC
    IFIP -- ip_blocks --> BD
    IPC -- ip_blocks --> BD
    XCI -- ip_blocks --> BD
    PIP -- ip_blocks --> BD
    IPC -- ip_blocks --> PRJ
    XCI -- ip_blocks --> PRJ
    PIP -- ip_blocks --> PRJ
    BD -- "block_designs<br/>VivadoBlockDesignInfo" --> PRJ
    XCI -. "deps<br/>VerilogInfo / VhdlInfo" .-> VL
```

Any of these can contribute `project_hooks`: Tcl sourced inside every
downstream `vivado_project` that folds the target in, right after
`create_project`.

## Simulation and export

- [`vivado_xsim_test`](./vivado_simulation.md) — export an xsim bundle
  at build time and run it as a Bazel `test` target, scanning the log
  for error and completion patterns.
- [`vivado_export_simulation`](./vivado_simulation.md) — run
  `export_simulation` for any simulator Vivado supports and stage the
  bundle, stopping there.
- [`vivado_compile_simlib`](./vivado_simulation.md) — pre-compile
  `unisim`, `secureip` and friends for a third-party simulator.
- [`vivado_project_export`](./vivado_project_export.md) — open the
  project, source a user `tcl_binary`, and capture whatever files or
  directories that script writes. Listed under
  [Project setup](#project-setup) too, since it is the general escape
  hatch rather than a simulation rule.

```mermaid
flowchart LR
    PRJ[vivado_project]
    XSIM["vivado_xsim_test<br/><i>bazel test</i>"]
    EXS["vivado_export_simulation<br/><i>export_simulation bundle</i>"]
    PEX["vivado_project_export<br/><i>user script, declared outs</i>"]
    SIMLIB["vivado_compile_simlib<br/><i>compile_simlib</i>"]
    EXT["third-party simulator<br/>(outside rules_vivado)"]

    PRJ -- "project<br/>VivadoProjectInfo" --> XSIM
    PRJ -- "project" --> EXS
    PRJ -- "project" --> PEX
    EXS -- VivadoExportSimulationInfo --> EXT
    SIMLIB -- VivadoCompiledSimlibInfo --> EXT
```

## Toolchain

- [`vivado_toolchain`](./vivado_toolchain.md) — declare a Vivado
  install for toolchain resolution. See
  [Toolchains](./toolchains.md) for the full workflow.

## Providers

- [`VivadoToolchainInfo` and friends](./vivado_providers.md) — the
  providers passed between phases (`VivadoProjectInfo`,
  `VivadoSynthCheckpointInfo`, `VivadoPlacementCheckpointInfo`,
  `VivadoRoutingCheckpointInfo`, `VivadoIPBlockInfo`,
  `VivadoBlockDesignInfo`, `VivadoInterfaceInfo`,
  `VivadoExportSimulationInfo`, and more).
