"""# rules_vivado settings"""

load("@bazel_skylib//rules:common_settings.bzl", "bool_flag")

visibility(["private"])

def incompatible_eager_tcl_hook_load(name = "incompatible_eager_tcl_hook_load"):
    """Declare the eager-tcl-hook-load flag.

    When enabled, each hook's transitive `tcl_library` srcs are sourced
    dependency-first ahead of the hook itself, instead of being reached
    through `package require` and `auto_path`.

    This is the file-to-file sharing model: the whole closure evaluates into
    Vivado's interpreter before the hook runs, so a script resolves procs it
    never declared a `package require` for. Off (the default), only the
    hook's own files are sourced, and a shared library has to carry
    `package provide` + `pkgIndex.tcl` for consumers to reach it.

    `incompatible_` because flipping it changes which scripts resolve, in
    both directions: enabling it hides missing `package require` lines, and
    disabling it surfaces every one of them at Vivado runtime. Intended as a
    migration lever for consumers porting a file-DAG build (a `-source`
    list built from a dependency graph) onto rules_vivado — not a mode to
    settle on, because eager loading also runs each file's top-level code
    for every hook in the closure, used or not.

    Being temporary, the flag is kept excisable. Everything that exists
    only to serve it is tagged `EAGER-TCL-HOOK-LOAD`, so `grep -rn
    EAGER-TCL-HOOK-LOAD` enumerates the removal set: this macro and its
    `BUILD.bazel` call, `tcl_hook_flag_attrs` and the `_eager_tcl_hook_load`
    attribute it puts on every hook-having rule, `_eager_tcl_srcs` and
    the `if eager:` branch in `hook_invocation`,
    and the flag-gated fixtures and tests under `//tests/analysis`.
    Nothing else reads the setting, and the default-path behaviour
    (`lazy_tcl_hook_load_test`, `hook_pkg_index_test`) is written against
    the unflagged rules, so it survives the removal unchanged.

    Args:
        name (str): name of the generated `bool_flag`.
    """
    bool_flag(
        name = name,
        build_setting_default = False,
    )
