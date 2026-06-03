"""Transitions used by rules_vivado."""

visibility([
    "//vivado/...",
    "//tests/...",
])

# `--extra_toolchains` toolchains are checked BEFORE any `register_toolchains`
# entries in resolution order. Prepending our Vivado tcl toolchain here
# guarantees it wins for any `tcl_binary` (or other `@rules_tcl//tcl:toolchain_type`
# consumer) reached under a hook attr — regardless of what the downstream
# user has registered elsewhere. Outside the transition our toolchain isn't
# in the list at all, so normal `tcl_binary` builds get the user's stock
# toolchain unchanged.
#
# Canonical label (via `Label(...)`), not the apparent `@rules_vivado//...`
# string: `--extra_toolchains` entries are resolved against the MAIN
# repo's mapping, which only knows this module under whatever name the
# root module gave it — or not at all when rules_vivado is a transitive
# dependency.
_VIVADO_TCL_TOOLCHAIN = str(Label("//vivado:vivado_tcl_toolchain"))

def _hook_transition_impl(settings, _attr):
    return {
        "//command_line_option:extra_toolchains": (
            [_VIVADO_TCL_TOOLCHAIN] + settings["//command_line_option:extra_toolchains"]
        ),
    }

hook_transition = transition(
    implementation = _hook_transition_impl,
    inputs = ["//command_line_option:extra_toolchains"],
    outputs = ["//command_line_option:extra_toolchains"],
)
