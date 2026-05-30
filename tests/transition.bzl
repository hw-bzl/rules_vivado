"""Top-level wrapper that pins both `--platforms` and
`--extra_execution_platforms` to the matching `//tests/toolchains:vivado_{ver}_platform`
for a set of target labels.

Build the wrapper itself (e.g. `bazel build //tests:all_bram_2025_1`) and every
target in `targets` is built under the transitioned config — including ones
that are `target_compatible_with` incompatible at the default platform or
tagged `manual` so they don't show up under `//...` on their own. This lets
`bazel build //...` cover the whole test universe without forcing every
otherwise-incompatible target to be individually invoked.

Toolchain resolution is platform-driven: every `toolchain()` in
`//tests/toolchains` is gated on `exec_compatible_with` against the
`//vivado/constraints/version:{ver}` constraint, so flipping the platform flips
the toolchain.
"""

# buildifier: disable=bzl-visibility
load("//vivado/private:versions.bzl", "VIVADO_VERSIONS")

_PLATFORM_PACKAGE = "//tests/toolchains"

def _platform_label_for(version):
    return "{}:vivado_{}_platform".format(_PLATFORM_PACKAGE, version.replace(".", "_"))

def _vivado_version_transition_impl(_settings, attr):
    if attr.vivado_version not in VIVADO_VERSIONS:
        fail("vivado_version '{}' not in known VIVADO_VERSIONS {}".format(
            attr.vivado_version,
            VIVADO_VERSIONS,
        ))
    platform = _platform_label_for(attr.vivado_version)
    return {
        # Prepending the exec platform forces Bazel to pick it over the
        # default-registered one during toolchain resolution, so the matching
        # vivado_toolchain (gated on `exec_compatible_with`) is selected.
        "//command_line_option:extra_execution_platforms": [platform],
        # Setting the target platform makes any `target_compatible_with`
        # constraints on the wrapped targets resolve against the version's
        # constraint_value.
        "//command_line_option:platforms": platform,
    }

_vivado_version_transition = transition(
    implementation = _vivado_version_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
        "//command_line_option:extra_execution_platforms",
    ],
)

def _with_vivado_version_impl(ctx):
    return [
        DefaultInfo(
            files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.targets]),
        ),
    ]

with_vivado_version = rule(
    doc = "Build every label in `targets` with `--platforms` and " +
          "`--extra_execution_platforms` pinned to the version's " +
          "`//tests/toolchains:vivado_{ver}_platform`. Lets one wrapper cover " +
          "several otherwise-incompatible targets.",
    implementation = _with_vivado_version_impl,
    attrs = {
        "targets": attr.label_list(
            doc = "The vivado_* targets to build under the pinned version.",
            mandatory = True,
            cfg = _vivado_version_transition,
        ),
        "vivado_version": attr.string(
            doc = "One of //vivado/private:versions.bzl VIVADO_VERSIONS.",
            mandatory = True,
        ),
    },
)
