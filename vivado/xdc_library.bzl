"""# xdc_library rule."""

load(":providers.bzl", "XdcInfo")

def _xdc_library_impl(ctx):
    # Topological: deps' srcs before this target's own srcs. This is
    # the ordering `vivado_project.data` relies on when a downstream
    # target references an xdc_library — the whole point of the rule.
    srcs = depset(
        direct = ctx.files.srcs,
        transitive = [dep[XdcInfo].srcs for dep in ctx.attr.deps],
        order = "topological",
    )

    return [
        # `DefaultInfo.files` IS the topological depset so
        # `vivado_project.data = [":my_xdc_library"]` picks up every
        # transitive constraint file in dep-first order via
        # `ctx.files.data`.
        DefaultInfo(files = srcs),
        XdcInfo(srcs = srcs),
    ]

xdc_library = rule(
    implementation = _xdc_library_impl,
    doc = """Bundle a set of Xilinx constraint files with other constraint \
files they must run after.

The only relationship this rule expresses is between XDC files —
`create_clock` before `set_clock_groups`, primary constraints before
secondary. It is deliberately independent of HDL: no `hdl_deps` attr, no
HDL provider re-export.

The transitive XDC set is exposed in `deps`-first (topological) order,
so consumers `read_xdc` files in the sequence inter-XDC ordering
requires. Two ways to consume it:

- **Direct.** List the target in `vivado_project.data`; Bazel walks the
  ordered `DefaultInfo.files` depset into the project's
  `$PROJECT_DATA_FILES` foreach in dep-first order.
- **Aspect.** `XdcInfo` is a first-class marker, so an aspect walking
  any dep graph can filter on `XdcInfo in target` and collect the
  constraint contributions.

Provides `XdcInfo`.
""",
    attrs = {
        "deps": attr.label_list(
            doc = (
                "Other `xdc_library` targets whose constraint files must " +
                "be `read_xdc`d BEFORE this target's own `srcs`."
            ),
            providers = [XdcInfo],
        ),
        "srcs": attr.label_list(
            doc = "Xilinx constraint files (`.xdc` / `.sdc`) this target owns.",
            allow_files = [".xdc", ".sdc"],
        ),
    },
    provides = [DefaultInfo, XdcInfo],
)
