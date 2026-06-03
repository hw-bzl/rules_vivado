"""Pin the file order the `vivado_project`-emitted `.project.tcl`
produces for a nested `verilog_library` tree with mixed HDL + XDC,
plus a direct `vivado_project.data` list.

See //tests/hdl_order:BUILD.bazel for the tree layout + rationale.
This test parses the emitted `set HDL_SOURCES { ... }`,
`set XDC_FILES { ... }`, and `set PROJECT_DATA_FILES { ... }` Tcl
literals into ordered Python lists and compares each against the
`EXPECTED_*` constants below. A failure prints the two lists
side-by-side.
"""

import os
import platform
import re
import unittest
from pathlib import Path

from python.runfiles import Runfiles

# `PROJECT_RLOCATIONPATH` is set on the `py_test`'s `env` via
# `$(rlocationpath :order_project)` so the test doesn't have to
# hard-code the emitted TCL's runfiles path.
_PROJECT_RLOCATIONPATH_ENV = "PROJECT_RLOCATIONPATH"

# `hdl_sources_data` in `//vivado/private:common.bzl` walks
# `VerilogInfo.deps.to_list() + [self]`. Depset default ordering
# ("default" / topological) puts deeper deps first, so a tree
# `a -> b -> c -> top` lands in the emitted lists in that order.
_EXPECTED_HDL_SOURCES = [
    "tests/hdl_order/a.sv",
    "tests/hdl_order/b.sv",
    "tests/hdl_order/c.sv",
    "tests/hdl_order/top.sv",
]

_EXPECTED_XDC_FILES = [
    "tests/hdl_order/a.xdc",
    "tests/hdl_order/b.xdc",
    "tests/hdl_order/c.xdc",
    "tests/hdl_order/top.xdc",
]

# `vivado_project.data` preserves the exact input list order for plain
# files, AND expands `xdc_library` targets in place with their
# transitive `XdcInfo.srcs` in topological (dep-first) order. The
# BUILD file lists:
#
#   data = ["xdc_a.xdc", ":lib_z", "xdc_b.xdc", "xdc_c.xdc"]
#
# where `:lib_z` depends on `:lib_y` depends on `:lib_x`, so the
# flattened order at load time is: plain file → dep chain → plain
# files.
_EXPECTED_PROJECT_DATA_FILES = [
    "tests/hdl_order/xdc_a.xdc",
    "tests/hdl_order/xdc_lib_x.xdc",
    "tests/hdl_order/xdc_lib_y.xdc",
    "tests/hdl_order/xdc_lib_z.xdc",
    "tests/hdl_order/xdc_b.xdc",
    "tests/hdl_order/xdc_c.xdc",
]


def _rlocation(runfiles: Runfiles, rlocationpath: str) -> Path:
    """Look up a runfile and ensure the file exists."""
    # TODO: https://github.com/periareon/rules_venv/issues/37
    source_repo = None
    if platform.system() == "Windows":
        source_repo = ""
    runfile = runfiles.Rlocation(rlocationpath, source_repo)
    if not runfile:
        raise FileNotFoundError(f"Failed to find runfile: {rlocationpath}")
    path = Path(runfile)
    if not path.exists():
        raise FileNotFoundError(f"Runfile does not exist: ({rlocationpath}) {path}")
    return path


def _extract_set_line(tcl_text: str, var_name: str) -> str:
    """Return the RHS of the first `set <var_name> ...` line in `tcl_text`.

    The emitted template writes both `HDL_SOURCES` and `XDC_FILES` on a
    single line so a line-based match is sufficient.
    """
    pattern = re.compile(rf"^set {re.escape(var_name)}\s+(.+)$", re.MULTILINE)
    match = pattern.search(tcl_text)
    if not match:
        raise AssertionError(f"no `set {var_name} ...` line found in emitted TCL")
    return match.group(1).strip()


def _parse_tcl_list(text: str) -> list[str]:
    """Split a Tcl list literal into its top-level items.

    Handles nested braces: a `{ a b c }` item at depth 1 is returned as
    the string `"a b c"` (its brace-stripped contents), so the caller
    can recurse if the item is itself a list. Bare (unbraced) items are
    returned as-is. Whitespace between items is skipped.

    Only the subset of Tcl-list syntax the emitted TCL actually uses is
    supported — no escapes, no double-quoted items.
    """
    text = text.strip()
    if text.startswith("{") and text.endswith("}"):
        text = text[1:-1].strip()

    items = []
    i = 0
    n = len(text)
    while i < n:
        while i < n and text[i].isspace():
            i += 1
        if i >= n:
            break
        if text[i] == "{":
            depth = 1
            start = i + 1
            i += 1
            while i < n and depth > 0:
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                i += 1
            if depth != 0:
                raise AssertionError(f"unbalanced braces in Tcl list: {text!r}")
            items.append(text[start : i - 1])
        else:
            start = i
            while i < n and not text[i].isspace():
                i += 1
            items.append(text[start:i])
    return items


def _extract_hdl_source_paths(line: str) -> list[str]:
    """Extract the ordered file paths from a `set HDL_SOURCES { ... }` value.

    Each element of the outer Tcl list is a 4-tuple:
    `{ kind path library standard }`. This returns just the paths,
    in emitted order.
    """
    return [_parse_tcl_list(tup)[1] for tup in _parse_tcl_list(line)]


def _extract_xdc_paths(line: str) -> list[str]:
    """Extract the ordered file paths from a `set XDC_FILES { ... }` value.

    `XDC_FILES` is a flat Tcl list of paths.
    """
    return _parse_tcl_list(line)


class HdlOrderTests(unittest.TestCase):
    """Verify dependency order in `vivado_project`'s emitted TCL."""

    @classmethod
    def setUpClass(cls) -> None:
        rlocationpath = os.environ.get(_PROJECT_RLOCATIONPATH_ENV)
        if not rlocationpath:
            raise EnvironmentError(
                f"env var {_PROJECT_RLOCATIONPATH_ENV} is unset; the "
                f"py_test rule should set it via "
                f"`env = {{\"{_PROJECT_RLOCATIONPATH_ENV}\": \"$(rlocationpath :order_project)\"}}`."
            )
        runfiles = Runfiles.Create()
        if not runfiles:
            raise EnvironmentError("Failed to locate runfiles.")
        cls.tcl_text = _rlocation(runfiles, rlocationpath).read_text(encoding="utf-8")

    def test_hdl_sources_order(self) -> None:
        line = _extract_set_line(self.tcl_text, "HDL_SOURCES")
        actual = _extract_hdl_source_paths(line)
        self.assertEqual(actual, _EXPECTED_HDL_SOURCES)

    def test_xdc_files_order(self) -> None:
        line = _extract_set_line(self.tcl_text, "XDC_FILES")
        actual = _extract_xdc_paths(line)
        self.assertEqual(actual, _EXPECTED_XDC_FILES)

    def test_project_data_files_order(self) -> None:
        """`vivado_project.data` accepts a mix of plain files and
        `xdc_library` targets. Plain files sit at their listed
        position; xdc_library targets expand in place with their
        transitive `XdcInfo.srcs` in topological order.
        """
        line = _extract_set_line(self.tcl_text, "PROJECT_DATA_FILES")
        # Same flat-list shape as XDC_FILES.
        actual = _extract_xdc_paths(line)
        self.assertEqual(actual, _EXPECTED_PROJECT_DATA_FILES)


if __name__ == "__main__":
    unittest.main()
