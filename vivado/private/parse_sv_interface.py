"""Parse a SystemVerilog interface file and extract signal definitions as JSON.

This is the default parser for the vivado_interface_definition rule.
It can be overridden via the `parser` attribute to support custom SV styles.

CLI: python3 parse_sv_interface.py --input <file.sv> --output <signals.json>

Parsing rules:
  - interface foo #(...)        -> interface_name = "foo"
  - logic [PARAM-1:0] sig;     -> width = "PARAM" (string, parameterized)
  - logic [31:0] sig;          -> width = 32 (int, literal)
  - logic sig;                 -> width = 1 (int)
  - // SPIRIT:ISADDRESS,REQUIRED  -> qualifier = "address", optional = false
  - // SPIRIT:ISDATA,OPTIONAL     -> qualifier = "data", optional = true
  - // SPIRIT:REQUIRED            -> qualifier = "", optional = false
  - modport master(output a, input b) -> a: direction_master="out", b: direction_master="in"
  - modport slave(input a, output b)  -> a: direction_slave="in", b: direction_slave="out"
  - modport monitor(...)              -> ignored
"""

import argparse
import json
import re
import sys


def parse_sv_interface(text):
    """Parse a SystemVerilog interface file and return signal definitions.

    Args:
        text: The full text content of the SV interface file.

    Returns:
        A dict with 'interface_name' and 'signals' keys.
    """
    interface_name = _extract_interface_name(text)
    signals = _extract_signals(text)
    _apply_modport_directions(text, signals)

    return {
        "interface_name": interface_name,
        "signals": signals,
    }


def _extract_interface_name(text):
    """Extract the interface name from the SV file."""
    match = re.search(r"^\s*interface\s+(\w+)", text, re.MULTILINE)
    if not match:
        raise ValueError("No interface declaration found in SV file")
    return match.group(1)


def _parse_width(width_expr):
    """Parse a width expression from a bit range.

    Args:
        width_expr: The MSB expression from [MSB:0], e.g. "ADDR_WIDTH-1", "31", "2"

    Returns:
        An int if the width is a literal, or a string if parameterized.
    """
    width_expr = width_expr.strip()

    # Check for PARAM-1 pattern (parameterized width)
    param_match = re.match(r"^(\w+)\s*-\s*1$", width_expr)
    if param_match:
        return param_match.group(1)

    # Check for literal number
    try:
        msb = int(width_expr)
        return msb + 1
    except ValueError:
        pass

    # Fallback: return expression as-is (unknown parameterized form)
    return width_expr


def _extract_signals(text):
    """Extract signal declarations and their SPIRIT annotations.

    Scans for lines with `logic [...] name;` preceded by optional SPIRIT comments.
    """
    signals = {}
    lines = text.split("\n")

    current_spirit = None  # (qualifier, optional) from most recent SPIRIT comment

    for line in lines:
        stripped = line.strip()

        # Check for SPIRIT comment
        spirit_match = re.match(r"^//\s*SPIRIT:\s*(.+)$", stripped)
        if spirit_match:
            current_spirit = _parse_spirit_comment(spirit_match.group(1))
            continue

        # Check for logic signal declaration
        sig_match = re.match(
            r"^logic\s+"  # keyword
            r"(?:\[\s*(.+?)\s*:\s*0\s*\]\s+)?"  # optional [MSB:0]
            r"(\w+)\s*;",  # signal name
            stripped,
        )
        if sig_match:
            msb_expr = sig_match.group(1)
            sig_name = sig_match.group(2)

            if msb_expr is not None:
                width = _parse_width(msb_expr)
            else:
                width = 1

            qualifier = ""
            optional = False
            if current_spirit is not None:
                qualifier, optional = current_spirit

            signals[sig_name] = {
                "name": sig_name,
                "width": width,
                "direction_master": "out",
                "direction_slave": "in",
                "qualifier": qualifier,
                "optional": optional,
            }
            current_spirit = None
            continue

        # Non-signal, non-SPIRIT line: reset SPIRIT state
        # (only reset if line is non-empty and non-comment)
        if stripped and not stripped.startswith("//"):
            current_spirit = None

    return signals


def _parse_spirit_comment(spirit_text):
    """Parse a SPIRIT annotation string.

    Examples:
        "ISADDRESS,REQUIRED" -> ("address", False)
        "ISDATA,OPTIONAL"    -> ("data", True)
        "REQUIRED"           -> ("", False)
        "OPTIONAL"           -> ("", True)
        "ISCLOCK,REQUIRED"   -> ("clock", False)
        "ISRESET,REQUIRED"   -> ("reset", False)

    Returns:
        (qualifier, optional) tuple
    """
    parts = [p.strip().upper() for p in spirit_text.split(",")]

    qualifier = ""
    optional = False

    for part in parts:
        if part == "ISADDRESS":
            qualifier = "address"
        elif part == "ISDATA":
            qualifier = "data"
        elif part == "ISCLOCK":
            qualifier = "clock"
        elif part == "ISRESET":
            qualifier = "reset"
        elif part == "OPTIONAL":
            optional = True
        elif part == "REQUIRED":
            optional = False

    return qualifier, optional


def _apply_modport_directions(text, signals):
    """Parse modport declarations and apply direction info to signals.

    Handles:
        modport master(output a, input b, ...)
        modport slave(input a, output b, ...)
        modport monitor(...) -> ignored
    """
    # Find all modport blocks - handle multi-line by joining
    # Remove newlines inside modport(...) to simplify parsing
    collapsed = re.sub(r"\n\s*", " ", text)

    for match in re.finditer(
        r"modport\s+(\w+)\s*\((.*?)\)\s*;",
        collapsed,
    ):
        modport_name = match.group(1).lower()
        body = match.group(2)

        if modport_name == "monitor":
            continue

        if modport_name == "master":
            dir_key = "direction_master"
        elif modport_name == "slave":
            dir_key = "direction_slave"
        else:
            continue

        # Parse "output a, b, input c, d" style
        current_dir = None
        for token in re.split(r"[,\s]+", body):
            token = token.strip()
            if not token:
                continue
            if token in ("input", "output", "inout"):
                current_dir = (
                    "in"
                    if token == "input"
                    else "out" if token == "output" else "inout"
                )
            elif current_dir and token in signals:
                signals[token][dir_key] = current_dir


def main():
    parser = argparse.ArgumentParser(
        description="Parse a SystemVerilog interface file into JSON signal definitions."
    )
    parser.add_argument("--input", required=True, help="Input .sv file path")
    parser.add_argument("--output", required=True, help="Output .json file path")
    args = parser.parse_args()

    with open(args.input, "r") as f:
        text = f.read()

    result = parse_sv_interface(text)

    with open(args.output, "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
