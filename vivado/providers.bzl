"""# Vivado providers."""

VivadoSynthCheckpointInfo = provider(
    doc = "Contains information at output of synthesis.",
    fields = {
        "checkpoint": "File: a Vivado synthesis checkpoint (.dcp).",
    },
)

VivadoPlacementCheckpointInfo = provider(
    doc = "Contains information at output of placement.",
    fields = {
        "checkpoint": "File: a Vivado placement checkpoint (.dcp).",
    },
)

VivadoRoutingCheckpointInfo = provider(
    doc = "Contains information at output of routing.",
    fields = {
        "checkpoint": "File: a Vivado post-route checkpoint (.dcp).",
    },
)

VivadoIPBlockInfo = provider(
    doc = "Info for a vivado ip block",
    fields = {
        "is_interface": "bool: True if this is an interface definition (repo-only, not instantiated via create_ip).",
        "library": "string: The library that the ip block belongs to.",
        "module_top": "string: The name of the ip block top module.",
        "repo": "list[File]: Directories containing the ip block (and any transitive ip block deps).",
        "vendor": "string: The vendor of the ip block.",
        "version": "string: The ip block version.",
    },
)

VivadoInterfaceInfo = provider(
    doc = "Info for a Vivado IP-XACT interface definition",
    fields = {
        "abstraction_definition": "File: The abstraction definition XML file.",
        "bus_definition": "File: The bus definition XML file.",
        "library": "string: The library VLNV component.",
        "name": "string: The interface name.",
        "setup_tcl": "File: The TCL setup file for IP packaging.",
        "vendor": "string: The vendor VLNV component.",
        "version": "string: The version VLNV component.",
    },
)
