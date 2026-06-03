"""Analysis-time coverage helpers for `//tests/analysis`.

`analysistest` is the only mechanism that gets a rule implementation to
run on a machine with no Vivado:

- `target_compatible_with` makes Bazel skip a target BEFORE its rule
  implementation runs, so the functional tests under `//tests/...` (all
  gated on `//vivado/constraints/version:2025.1`) analyze to nothing off
  a Vivado platform.
- `--build_tag_filters=-requires-vivado` — the repo default from
  `.bazelrc` — prunes at the LOADING/ANALYSIS step, not the execution
  step. A `requests-vivado`-tagged target named on the command line is
  never configured at all.

A tag filter only applies to targets named on the command line, though.
An untagged `analysistest` target IS analyzed, and analyzing it forces
Bazel to configure its `target_under_test` — running that rule's
implementation — without ever executing the actions the implementation
registers. That is exactly the coverage this package wants.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//vivado:providers.bzl", "VivadoProjectInfo")

def _analyzes_impl(ctx):
    """Assert the target under test configured and registered work."""
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(
        env,
        DefaultInfo in target,
        "{} advertises no DefaultInfo".format(target.label),
    )
    if ctx.attr.expect_actions:
        asserts.true(
            env,
            len(analysistest.target_actions(env)) > 0,
            "{} registered no actions".format(target.label),
        )

    return analysistest.end(env)

_analyzes_test = analysistest.make(
    _analyzes_impl,
    attrs = {
        "expect_actions": attr.bool(
            doc = ("Whether the rule is expected to register at least one " +
                   "action. False only for pure provider-forwarding rules " +
                   "such as `xdc_library`."),
            default = True,
        ),
    },
)

def analyzes_test_suite(name, targets, action_free = []):
    """Assert every target in `targets` survives analysis.

    Args:
        name (str): name of the generated `test_suite`.
        targets (list[str]): labels to configure. Each gets its own test
            so a failure names the offending rule, not the whole package.
        action_free (list[str]): subset of `targets` whose rules
            legitimately register no actions (they only re-package their
            deps' files into providers), so the "registered work"
            assertion is skipped.
    """
    tests = []
    for target in targets:
        test_name = "{}_analyzes_test".format(target.lstrip(":"))
        _analyzes_test(
            name = test_name,
            expect_actions = target not in action_free,
            target_under_test = target,
        )
        tests.append(test_name)

    native.test_suite(
        name = name,
        tests = tests,
    )

def _project_export_outputs_impl(ctx):
    """`outs` / `out_dirs` must reach DefaultInfo as declared artifacts.

    Regression guard: `vivado_project_export` shipped calling
    `declare_file` on `ctx.attr.outs`, which is a list of Labels, not
    strings. Nothing instantiated the rule, so the type error never
    surfaced.
    """
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    files = target[DefaultInfo].files.to_list()
    basenames = [f.basename for f in files]
    asserts.true(
        env,
        "part.txt" in basenames,
        "declared `outs` entry missing from DefaultInfo: {}".format(basenames),
    )

    dirs = [f.basename for f in files if f.is_directory]
    asserts.equals(env, ["reports"], dirs)

    return analysistest.end(env)

project_export_outputs_test = analysistest.make(_project_export_outputs_impl)

def _hook_pkg_index_impl(ctx):
    """A `tcl_library` hook stages `pkgIndex.tcl` but never sources it.

    Regression guard: `hook_invocation` used to add every file a
    non-executable hook target produces to the sourced list. The moment a
    shared `tcl_library` gained a `pkgIndex.tcl` — so `package require`
    consumers could reach it through `auto_path` — every design that also
    passed that library through a hook attr died inside Vivado with
    `can't read "dir": no such variable`. A package index is meant to be
    evaluated by Tcl's package machinery, which binds `$dir` first;
    `source`ing it directly cannot work.

    Skipping it keeps one `tcl_library` usable by both consumer styles:
    hook consumers source its real srcs file-by-file, `package require`
    consumers find it on `auto_path`.
    """
    env = analysistest.begin(ctx)

    expansions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "TemplateExpand"
    ]
    asserts.equals(env, 1, len(expansions), "expected one TemplateExpand")
    sourced = expansions[0].substitutions["{{PRE_HOOKS}}"]

    asserts.true(
        env,
        "util.tcl" in sourced,
        "hook library's srcs missing from PRE_HOOKS: {}".format(sourced),
    )
    asserts.false(
        env,
        "pkgIndex.tcl" in sourced,
        "package index must not be sourced as a hook: {}".format(sourced),
    )

    staged = [
        f.basename
        for action in analysistest.target_actions(env)
        for f in action.inputs.to_list()
    ]
    asserts.true(
        env,
        "pkgIndex.tcl" in staged,
        "package index must still stage into the sandbox: {}".format(staged),
    )

    return analysistest.end(env)

hook_pkg_index_test = analysistest.make(_hook_pkg_index_impl)

# EAGER-TCL-HOOK-LOAD: this constant and the four flag-gated tests that
# use it (`eager_tcl_hook_load_test`, `external_tcl_hook_load_test`,
# `hook_source_once_test`, `script_tcl_closure_test`) are the flag's whole
# test surface here. `lazy_tcl_hook_load_test` reads the default path
# and stays.
#
# Canonicalized: `analysistest`'s `config_settings` keys are resolved in
# bazel_skylib's repo context, not this one, so a bare `//vivado/...`
# string looks for the package inside `@bazel_skylib`.
_EAGER_FLAG = str(Label("//vivado/settings:incompatible_eager_tcl_hook_load"))

def _pre_hooks_of(env):
    """The `{{PRE_HOOKS}}` Tcl list the target under test will source."""
    expansions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "TemplateExpand"
    ]
    asserts.equals(env, 1, len(expansions), "expected one TemplateExpand")
    return expansions[0].substitutions["{{PRE_HOOKS}}"]

def _lazy_tcl_hook_load_impl(ctx):
    """Default: a hook sources its own srcs, not its deps'.

    `//tests/analysis/tcl:leaf` depends on `:base`, but only `leaf.tcl`
    is in the hook target's `DefaultInfo.files`. `base.tcl` stays
    unsourced — a script that wants it must `package require
    analysis_tcl_base`, which resolves through `auto_path`.
    """
    env = analysistest.begin(ctx)
    sourced = _pre_hooks_of(env)

    asserts.true(
        env,
        "leaf.tcl" in sourced,
        "hook's own srcs missing from PRE_HOOKS: {}".format(sourced),
    )
    asserts.false(
        env,
        "base.tcl" in sourced,
        "transitive dep must not be sourced by default: {}".format(sourced),
    )

    return analysistest.end(env)

lazy_tcl_hook_load_test = analysistest.make(_lazy_tcl_hook_load_impl)

def _eager_tcl_hook_load_impl(ctx):
    """Flag on: the hook's whole `tcl_library` closure sources first.

    This is the flat file-to-file model — the closure evaluates into
    Vivado's interpreter before the hook runs, so `leaf.tcl` can call
    `::analysis_tcl_base::tag` without a `package require`. Order
    matters as much as membership: `TclInfo.transitive_srcs` is a
    postorder depset, so a dep's files must land ahead of the files that
    need them, or eager loading buys nothing over lazy.
    """
    env = analysistest.begin(ctx)
    sourced = _pre_hooks_of(env)

    asserts.true(
        env,
        "base.tcl" in sourced,
        "transitive dep missing from PRE_HOOKS under the flag: {}".format(sourced),
    )
    asserts.true(
        env,
        sourced.index("base.tcl") < sourced.index("leaf.tcl"),
        "dep must source before its dependent: {}".format(sourced),
    )

    # Eager loading changes WHICH files get sourced, never the
    # `pkgIndex.tcl` carve-out — those still bind `$dir` and still
    # cannot be `source`d directly.
    asserts.false(
        env,
        "pkgIndex.tcl" in sourced,
        "package index must not be sourced under the flag: {}".format(sourced),
    )

    return analysistest.end(env)

eager_tcl_hook_load_test = analysistest.make(
    _eager_tcl_hook_load_impl,
    config_settings = {_EAGER_FLAG: True},
)

def _external_tcl_hook_load_impl(ctx):
    """Flag on: eager loading stops at the repository boundary.

    `//tests/analysis/tcl:external_dep` depends on
    `@rules_tcl//tcl/runfiles`, a packaged library that binds `$dir` for
    `rlocation` when `package require` loads it. Sourcing `runfiles.tcl`
    as a bare file would run it with `$dir` unset, so the closure walk
    has to skip anything a foreign repo owns while still sourcing the
    hook's own first-party srcs.
    """
    env = analysistest.begin(ctx)
    sourced = _pre_hooks_of(env)

    asserts.true(
        env,
        "external_dep.tcl" in sourced,
        "first-party hook src missing from PRE_HOOKS: {}".format(sourced),
    )
    asserts.false(
        env,
        "runfiles.tcl" in sourced,
        "external repo package must not be sourced: {}".format(sourced),
    )

    return analysistest.end(env)

external_tcl_hook_load_test = analysistest.make(
    _external_tcl_hook_load_impl,
    config_settings = {_EAGER_FLAG: True},
)

def _hook_source_once_impl(ctx):
    """A file reachable by two routes is still sourced exactly once.

    `pre_hooks` names `:base` directly and `:leaf`, which depends on it.
    Both routes reach `base.tcl`, but Tcl has no include guard, so the
    emitted list must carry it once — at the earlier of the two
    positions, which is the one that keeps it ahead of `leaf.tcl`.
    """
    env = analysistest.begin(ctx)
    sourced = _pre_hooks_of(env)

    asserts.equals(
        env,
        1,
        sourced.count("base.tcl"),
        "doubly-reachable dep must source once: {}".format(sourced),
    )
    asserts.true(
        env,
        sourced.index("base.tcl") < sourced.index("leaf.tcl"),
        "dedup must keep the dependency-first position: {}".format(sourced),
    )

    return analysistest.end(env)

hook_source_once_test = analysistest.make(
    _hook_source_once_impl,
    config_settings = {_EAGER_FLAG: True},
)

def _script_tcl_closure_impl(ctx):
    """Flag on: the `script` attr's own closure sources too.

    `script` is a `tcl_binary`, so its `tcl_library` deps are staged into
    runfiles — but the template sources exactly one path,
    `$BD_SCRIPT`, and nothing puts the closure in front of it. A design
    script calling a helper namespace it correctly declared in `deps`
    then dies with `invalid command name`. Under the flag the closure is
    appended after the hooks, which lands it immediately before
    `source $BD_SCRIPT`.
    """
    env = analysistest.begin(ctx)
    sourced = _pre_hooks_of(env)

    asserts.true(
        env,
        "leaf.tcl" in sourced,
        "script's dep missing from PRE_HOOKS under the flag: {}".format(sourced),
    )
    asserts.true(
        env,
        "base.tcl" in sourced,
        "script's transitive dep missing from PRE_HOOKS: {}".format(sourced),
    )

    # No ordering assertion, deliberately. `TclInfo.transitive_srcs`
    # declares `order = "postorder"`, but rules_tcl builds it by
    # appending each dep's own `srcs` ahead of that dep's
    # `transitive_srcs`, so the flattened list runs dependent-first from
    # the second level down. `eager_tcl_hook_load_test` gets the order it
    # wants only because a hook's own srcs are appended separately, after
    # its closure. Fixing that belongs upstream in rules_tcl.
    return analysistest.end(env)

script_tcl_closure_test = analysistest.make(
    _script_tcl_closure_impl,
    config_settings = {_EAGER_FLAG: True},
)

def _project_xdc_order_impl(ctx):
    """`VivadoProjectInfo.xdc` must match the `data =` load order.

    The provider advertises the exact sequence the emitted
    `$PROJECT_DATA_FILES` loop walks: plain files at their listed
    position, and an `xdc_library`'s dep-first depset flattened in place
    where the target appears. Building the depset with a
    `direct`/`transitive` split instead would group all `xdc_library`
    content ahead of all plain files and advertise an order the action
    never uses.
    """
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    actual = [f.basename for f in target[VivadoProjectInfo].xdc.to_list()]
    asserts.equals(env, ctx.attr.expected, actual)

    return analysistest.end(env)

project_xdc_order_test = analysistest.make(
    _project_xdc_order_impl,
    attrs = {
        "expected": attr.string_list(
            doc = "Expected `VivadoProjectInfo.xdc` basenames, in order.",
            mandatory = True,
        ),
    },
)
