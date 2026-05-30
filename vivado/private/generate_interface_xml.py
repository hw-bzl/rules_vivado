"""Generate IP-XACT XML and TCL files from parsed signal definitions.

Reads a signals JSON file (produced by parse_sv_interface.py) and template
files, performs placeholder substitution, and writes the three output files:
  - Bus definition XML
  - Abstraction definition XML
  - Interface setup TCL

This script is internal to the vivado_interface_definition rule and should
not need to be overridden.
"""

import argparse
import json
import sys


def generate_port_xml(signal):
    """Generate XML for a single port in the abstraction definition.

    Args:
        signal: A dict with keys: name, direction_master, direction_slave,
                qualifier, width, optional

    Returns:
        XML string for the port definition.
    """
    logical_name = signal["name"].upper()
    presence = "optional" if signal.get("optional", False) else "required"

    # Build qualifier section if needed
    qualifier_xml = ""
    qualifier = signal.get("qualifier", "")
    if qualifier == "address":
        qualifier_xml = (
            "\n                <spirit:qualifier>"
            "\n                    <spirit:isAddress>true</spirit:isAddress>"
            "\n                </spirit:qualifier>"
        )
    elif qualifier == "data":
        qualifier_xml = (
            "\n                <spirit:qualifier>"
            "\n                    <spirit:isData>true</spirit:isData>"
            "\n                </spirit:qualifier>"
        )
    elif qualifier == "clock":
        qualifier_xml = (
            "\n                <spirit:qualifier>"
            "\n                    <spirit:isClock>true</spirit:isClock>"
            "\n                </spirit:qualifier>"
        )
    elif qualifier == "reset":
        qualifier_xml = (
            "\n                <spirit:qualifier>"
            "\n                    <spirit:isReset>true</spirit:isReset>"
            "\n                </spirit:qualifier>"
        )

    # Width element
    width = signal.get("width", 1)
    width_xml = ""
    if isinstance(width, int):
        width_xml = "\n                    <spirit:width>{}</spirit:width>".format(
            width
        )
    # String (parameterized) width: don't include width element

    dir_master = signal.get("direction_master", "out")
    dir_slave = signal.get("direction_slave", "in")

    return (
        "\n        <spirit:port>"
        "\n            <spirit:logicalName>{logical_name}</spirit:logicalName>"
        "\n            <spirit:description>{name} signal</spirit:description>"
        "\n            <spirit:wire>{qualifier_xml}"
        "\n                <spirit:onMaster>"
        "\n                    <spirit:presence>{presence}</spirit:presence>{width_xml}"
        "\n                    <spirit:direction>{dir_master}</spirit:direction>"
        "\n                </spirit:onMaster>"
        "\n                <spirit:onSlave>"
        "\n                    <spirit:presence>{presence}</spirit:presence>{width_xml}"
        "\n                    <spirit:direction>{dir_slave}</spirit:direction>"
        "\n                </spirit:onSlave>"
        "\n            </spirit:wire>"
        "\n        </spirit:port>"
    ).format(
        logical_name=logical_name,
        name=signal["name"],
        qualifier_xml=qualifier_xml,
        presence=presence,
        width_xml=width_xml,
        dir_master=dir_master,
        dir_slave=dir_slave,
    )


def substitute_template(template_text, substitutions):
    """Replace {{PLACEHOLDER}} strings in template text."""
    result = template_text
    for key, value in substitutions.items():
        result = result.replace(key, value)
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Generate IP-XACT XML and TCL from signal definitions."
    )
    parser.add_argument("--signals-json", required=True, help="Path to signals JSON")
    parser.add_argument("--bus-def-template", required=True)
    parser.add_argument("--abs-def-template", required=True)
    parser.add_argument("--setup-tcl-template", required=True)
    parser.add_argument("--bus-def-output", required=True)
    parser.add_argument("--abs-def-output", required=True)
    parser.add_argument("--setup-tcl-output", required=True)
    parser.add_argument("--vendor", required=True)
    parser.add_argument("--library", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--direct-connection", default="true")
    parser.add_argument("--is-addressable", default="true")
    parser.add_argument("--max-masters", default="1")
    parser.add_argument("--max-slaves", default="1")
    parser.add_argument("--description", default="")
    args = parser.parse_args()

    # Read signals JSON
    with open(args.signals_json, "r") as f:
        data = json.load(f)

    signals = data["signals"]

    # Generate ports XML
    ports_xml = ""
    for sig_name, signal in signals.items():
        ports_xml += generate_port_xml(signal)

    # Display name
    display_name = args.name.replace("_", " ").title() + " Interface"
    description = args.description if args.description else display_name
    version_underscore = args.version.replace(".", "_")

    # Common substitutions
    common_subs = {
        "{{VENDOR}}": args.vendor,
        "{{LIBRARY}}": args.library,
        "{{NAME}}": args.name,
        "{{VERSION}}": args.version,
        "{{DISPLAY_NAME}}": display_name,
    }

    # Bus definition
    with open(args.bus_def_template, "r") as f:
        bus_def_tmpl = f.read()
    bus_def_subs = dict(common_subs)
    bus_def_subs.update(
        {
            "{{DIRECT_CONNECTION}}": args.direct_connection,
            "{{IS_ADDRESSABLE}}": args.is_addressable,
            "{{MAX_MASTERS}}": args.max_masters,
            "{{MAX_SLAVES}}": args.max_slaves,
            "{{DESCRIPTION}}": description,
        }
    )
    with open(args.bus_def_output, "w") as f:
        f.write(substitute_template(bus_def_tmpl, bus_def_subs))

    # Abstraction definition
    with open(args.abs_def_template, "r") as f:
        abs_def_tmpl = f.read()
    abs_def_subs = dict(common_subs)
    abs_def_subs["{{PORTS_XML}}"] = ports_xml
    with open(args.abs_def_output, "w") as f:
        f.write(substitute_template(abs_def_tmpl, abs_def_subs))

    # Setup TCL - needs SRC_DIR and VERSION_UNDERSCORE
    with open(args.setup_tcl_template, "r") as f:
        setup_tcl_tmpl = f.read()
    # SRC_DIR is the directory containing the output bus def file
    import os

    src_dir = os.path.dirname(args.bus_def_output)
    setup_tcl_subs = dict(common_subs)
    setup_tcl_subs.update(
        {
            "{{VERSION_UNDERSCORE}}": version_underscore,
            "{{SRC_DIR}}": src_dir,
        }
    )
    with open(args.setup_tcl_output, "w") as f:
        f.write(substitute_template(setup_tcl_tmpl, setup_tcl_subs))


if __name__ == "__main__":
    main()
