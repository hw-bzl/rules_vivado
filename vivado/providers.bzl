"""Describe Vivado providers."""

VivadoSynthCheckpointInfo = provider(
    doc = "Contains information at output of synthesis.",
    fields = {
        "checkpoint": "A vivado checkpoint.",
    },
)

VivadoPlacementCheckpointInfo = provider(
    doc = "Contains information at output of placement.",
    fields = {
        "checkpoint": "A vivado checkpoint.",
    },
)

VivadoRoutingCheckpointInfo = provider(
    doc = "Contains information at output of routing.",
    fields = {
        "checkpoint": "A vivado checkpoint.",
    },
)

VivadoIPBlockInfo = provider(
    doc = "Info for a vivado ip block",
    fields = {
        "library": "The library that the ip block belongs to.",
        "module_top": "The name of the ip block top module.",
        "repo": "Repo containing ip block.",
        "vendor": "The vendor of the ip block.",
        "version": "The ip block version.",
    },
)

VivadoInterfaceInfo = provider(
    doc = "Info for a Vivado IP-XACT interface definition",
    fields = {
        "name": "The interface name.",
        "vendor": "The vendor VLNV component.",
        "library": "The library VLNV component.",
        "version": "The version VLNV component.",
        "bus_definition": "The bus definition XML file.",
        "abstraction_definition": "The abstraction definition XML file.",
        "setup_tcl": "The TCL setup file for IP packaging.",
    },
)
