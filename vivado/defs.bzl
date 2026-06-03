"""# Public entrypoint for rules_vivado.

Re-exports every rule, macro and provider from the phase-grouped files under
`//vivado` and the toolchain rule. Users who only need a subset can load
directly from the phase files (e.g. `load("//vivado:synthesis.bzl", ...)`)
or from `//vivado:providers.bzl` instead of going through this aggregator.

The providers are part of the public API: a rule outside this repo that
wants to consume a checkpoint, feed a `vivado_project`, or wrap a phase
needs them to declare `providers = [...]` on its attrs and to read the
fields off its deps.
"""

load(
    "//vivado:bitstream.bzl",
    _vivado_bitstream = "vivado_bitstream",
    _vivado_device_image = "vivado_device_image",
)
load("//vivado:block_design.bzl", _vivado_block_design = "vivado_block_design")
load("//vivado:debug_probes.bzl", _vivado_debug_probes = "vivado_debug_probes")
load("//vivado:hw_platform.bzl", _vivado_hw_platform = "vivado_hw_platform")
load(
    "//vivado:implementation.bzl",
    _vivado_place_optimize = "vivado_place_optimize",
    _vivado_placement = "vivado_placement",
    _vivado_routing = "vivado_routing",
)
load(
    "//vivado:ip.bzl",
    _vivado_interface_definition = "vivado_interface_definition",
    _vivado_interface_ip = "vivado_interface_ip",
    _vivado_ip_core = "vivado_ip_core",
    _vivado_xci = "vivado_xci",
)
load("//vivado:packaged_ip.bzl", _vivado_packaged_ip = "vivado_packaged_ip")
load("//vivado:project.bzl", _vivado_project = "vivado_project")
load("//vivado:project_export.bzl", _vivado_project_export = "vivado_project_export")
load(
    "//vivado:providers.bzl",
    _VivadoBlockDesignInfo = "VivadoBlockDesignInfo",
    _VivadoCompiledSimlibInfo = "VivadoCompiledSimlibInfo",
    _VivadoDebugProbesInfo = "VivadoDebugProbesInfo",
    _VivadoExportSimulationInfo = "VivadoExportSimulationInfo",
    _VivadoHwPlatformInfo = "VivadoHwPlatformInfo",
    _VivadoIPBlockInfo = "VivadoIPBlockInfo",
    _VivadoInterfaceInfo = "VivadoInterfaceInfo",
    _VivadoLogInfo = "VivadoLogInfo",
    _VivadoPlacementCheckpointInfo = "VivadoPlacementCheckpointInfo",
    _VivadoProjectInfo = "VivadoProjectInfo",
    _VivadoReportsInfo = "VivadoReportsInfo",
    _VivadoRoutingCheckpointInfo = "VivadoRoutingCheckpointInfo",
    _VivadoSynthCheckpointInfo = "VivadoSynthCheckpointInfo",
    _XdcInfo = "XdcInfo",
)
load(
    "//vivado:simulation.bzl",
    _vivado_compile_simlib = "vivado_compile_simlib",
    _vivado_export_simulation = "vivado_export_simulation",
    _vivado_xsim_test = "vivado_xsim_test",
)
load(
    "//vivado:synthesis.bzl",
    _vivado_synthesis = "vivado_synthesis",
    _vivado_synthesis_optimize = "vivado_synthesis_optimize",
)
load("//vivado:toolchain.bzl", _VivadoToolchainInfo = "VivadoToolchainInfo", _vivado_toolchain = "vivado_toolchain")
load("//vivado:xdc_library.bzl", _xdc_library = "xdc_library")

VivadoBlockDesignInfo = _VivadoBlockDesignInfo
VivadoCompiledSimlibInfo = _VivadoCompiledSimlibInfo
VivadoDebugProbesInfo = _VivadoDebugProbesInfo
VivadoExportSimulationInfo = _VivadoExportSimulationInfo
VivadoHwPlatformInfo = _VivadoHwPlatformInfo
VivadoIPBlockInfo = _VivadoIPBlockInfo
VivadoInterfaceInfo = _VivadoInterfaceInfo
VivadoLogInfo = _VivadoLogInfo
VivadoPlacementCheckpointInfo = _VivadoPlacementCheckpointInfo
VivadoProjectInfo = _VivadoProjectInfo
VivadoReportsInfo = _VivadoReportsInfo
VivadoRoutingCheckpointInfo = _VivadoRoutingCheckpointInfo
VivadoSynthCheckpointInfo = _VivadoSynthCheckpointInfo
VivadoToolchainInfo = _VivadoToolchainInfo
XdcInfo = _XdcInfo
vivado_bitstream = _vivado_bitstream
vivado_block_design = _vivado_block_design
vivado_compile_simlib = _vivado_compile_simlib
vivado_debug_probes = _vivado_debug_probes
vivado_device_image = _vivado_device_image
vivado_export_simulation = _vivado_export_simulation
vivado_hw_platform = _vivado_hw_platform
vivado_interface_definition = _vivado_interface_definition
vivado_interface_ip = _vivado_interface_ip
vivado_ip_core = _vivado_ip_core
vivado_packaged_ip = _vivado_packaged_ip
vivado_place_optimize = _vivado_place_optimize
vivado_placement = _vivado_placement
vivado_project = _vivado_project
vivado_project_export = _vivado_project_export
vivado_routing = _vivado_routing
vivado_synthesis = _vivado_synthesis
vivado_synthesis_optimize = _vivado_synthesis_optimize
vivado_toolchain = _vivado_toolchain
vivado_xci = _vivado_xci
vivado_xsim_test = _vivado_xsim_test
xdc_library = _xdc_library
