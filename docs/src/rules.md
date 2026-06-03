# Rules

Every public rule in `rules_vivado`, grouped by the build phase it
belongs to. All of them resolve their Xilinx install through a
registered [`vivado_toolchain`](./toolchains.md). See
[Rule flow](./flow.md) for how they connect.

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

## Synthesis

- [`vivado_synthesis`](./vivado_synthesis.md) — run synthesis on a
  `vivado_project` and produce a synthesis checkpoint (`.dcp`).
- [`vivado_synthesis_optimize`](./vivado_synthesis.md) — post-synthesis
  optimization pass on a synthesis checkpoint.

## Implementation

- [`vivado_placement`](./vivado_implementation.md) — placement on a
  synthesis checkpoint.
- [`vivado_place_optimize`](./vivado_implementation.md) —
  post-placement optimization on a placement checkpoint.
- [`vivado_routing`](./vivado_implementation.md) — routing on a
  placement checkpoint.

## Hand-off artifacts

- [`vivado_bitstream`](./vivado_bitstream.md) — emit the final `.bit`
  from a routing checkpoint.
- [`vivado_device_image`](./vivado_bitstream.md) — emit a Versal `.pdi`
  from a routing checkpoint.
- [`vivado_hw_platform`](./vivado_hw_platform.md) — emit the `.xsa`
  hardware platform for Vitis / PetaLinux from a routing checkpoint.
- [`vivado_debug_probes`](./vivado_debug_probes.md) — emit the `.ltx`
  probe file for Hardware Manager from any phase checkpoint.

## IP composition

- [`vivado_xci`](./vivado_ip.md) — configure a Xilinx-catalog IP from a
  Tcl script into a consumable IP repo.
- [`vivado_ip_core`](./vivado_ip.md) — package an HDL module as a
  Vivado IP core.
- [`vivado_interface_definition`](./vivado_ip.md) — generate IP-XACT
  bus + abstraction definitions from a SystemVerilog interface.
- [`vivado_interface_ip`](./vivado_ip.md) — register an interface
  definition as an IP catalog entry so block designs can use it.
- [`vivado_packaged_ip`](./vivado_packaged_ip.md) — stage an
  already-packaged IP repo for `ip_blocks`.
- [`vivado_block_design`](./vivado_block_design.md) — build a `.bd` from
  a Tcl script for `vivado_project.block_designs`.

## Simulation

- [`vivado_xsim_test`](./vivado_simulation.md) — run a Vivado XSim
  simulation as a Bazel `test` target.
- [`vivado_export_simulation`](./vivado_simulation.md) — run
  `export_simulation` for any supported simulator and stage the bundle.
- [`vivado_compile_simlib`](./vivado_simulation.md) — pre-compile the
  Xilinx simulation libraries for a third-party simulator.

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
