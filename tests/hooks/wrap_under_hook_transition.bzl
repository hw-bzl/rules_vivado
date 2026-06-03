"""Test helper: expose the `hook_transition`-transitioned output of a
`tcl_binary` (or any hook target) as a plain target so a sibling
`sh_test` can consume the generated Vivado hook wrapper as `data`.

Production code applies `hook_transition` via `cfg = hook_transition` on
the hook attrs of every Vivado rule. This rule mirrors that shape for
test-time inspection without needing a real `vivado_export_simulation`
(which requires a Vivado license).
"""

load("//vivado/private:transitions.bzl", "hook_transition")

def _wrap_impl(ctx):
    inner = ctx.attr.binary[0][DefaultInfo]
    return [DefaultInfo(
        files = inner.files,
        runfiles = inner.default_runfiles,
    )]

wrap_under_hook_transition = rule(
    implementation = _wrap_impl,
    attrs = {
        "binary": attr.label(
            doc = "Target to analyze under the Vivado hook transition.",
            cfg = hook_transition,
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
