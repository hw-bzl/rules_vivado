"""Public entrypoint for rules_vivado.

Re-exports every rule and macro from the phase-grouped files under `//vivado`
and the toolchain rule. Users who only need a subset of rules can load
directly from the phase files (e.g. `load("//vivado:synthesis.bzl", ...)`)
instead of going through this aggregator.
"""

load("//vivado:bitstream.bzl", _vivado_write_bitstream = "vivado_write_bitstream")
load("//vivado:flow.bzl", _vivado_flow = "vivado_flow")
load(
    "//vivado:implementation.bzl",
    _vivado_place_optimize = "vivado_place_optimize",
    _vivado_placement = "vivado_placement",
    _vivado_routing = "vivado_routing",
)
load(
    "//vivado:ip.bzl",
    _vivado_create_interface_ip = "vivado_create_interface_ip",
    _vivado_create_ip = "vivado_create_ip",
    _vivado_interface_definition = "vivado_interface_definition",
)
load("//vivado:project.bzl", _vivado_create_project = "vivado_create_project")
load("//vivado:simulation.bzl", _xsim_test = "xsim_test")
load(
    "//vivado:synthesis.bzl",
    _vivado_synthesis_optimize = "vivado_synthesis_optimize",
    _vivado_synthesize = "vivado_synthesize",
)
load("//vivado:toolchain.bzl", _VivadoToolchainInfo = "VivadoToolchainInfo", _vivado_toolchain = "vivado_toolchain")

VivadoToolchainInfo = _VivadoToolchainInfo
vivado_toolchain = _vivado_toolchain

vivado_create_project = _vivado_create_project
vivado_synthesize = _vivado_synthesize
vivado_synthesis_optimize = _vivado_synthesis_optimize
vivado_placement = _vivado_placement
vivado_place_optimize = _vivado_place_optimize
vivado_routing = _vivado_routing
vivado_write_bitstream = _vivado_write_bitstream
vivado_flow = _vivado_flow
xsim_test = _xsim_test
vivado_create_ip = _vivado_create_ip
vivado_interface_definition = _vivado_interface_definition
vivado_create_interface_ip = _vivado_create_interface_ip
