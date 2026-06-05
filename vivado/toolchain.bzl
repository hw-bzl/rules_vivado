"""# Toolchain for the Xilinx Vivado tool.

Defines `VivadoToolchainInfo` and the `vivado_toolchain` rule. Users register a
`vivado_toolchain` instance via `register_toolchains(...)` against the
`//vivado:toolchain_type` toolchain type so every `vivado_*` rule automatically
resolves the Xilinx environment.

# Quickstart

1. Declare a `vivado_toolchain` and a `toolchain()` wrapper in BUILD. Put your
   Vivado install path and license server in `env`:

   ```starlark
   load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

   vivado_toolchain(
       name = "vivado_local",
       env = {
           "XILINX_VIVADO": "/opt/Xilinx/Vivado/2024.2",
           "PATH": "/opt/Xilinx/Vivado/2024.2/bin:/usr/bin:/bin",
           "XILINXD_LICENSE_FILE": "2100@license.example.com",
           "HOME": "/tmp",
       },
   )

   toolchain(
       name = "vivado_toolchain",
       toolchain = ":vivado_local",
       toolchain_type = "@rules_vivado//vivado:toolchain_type",
   )
   ```

2. Register it from MODULE.bazel:

   ```starlark
   register_toolchains("//tools/vivado:vivado_toolchain")
   ```

Every `vivado_*` rule resolves this toolchain automatically.

`xilinx_env` is an optional escape hatch — a shell script sourced inside the
action immediately before `vivado` runs — for shell-side env composition that
`env` cannot express. Prefer `env` and reach for it only when needed.

# Constraining toolchains

Register multiple `vivado_toolchain` instances side-by-side and let Bazel pick
one per action via `exec_compatible_with` against the per-version
`constraint_value`s in `//vivado/constraints/BUILD.bazel`. Each constraint
corresponds to one entry in `//vivado/private:versions.bzl` VIVADO_VERSIONS.

```starlark
load("@rules_vivado//vivado:toolchain.bzl", "vivado_toolchain")

vivado_toolchain(
    name = "vivado_2024_2",
    env = {
        "XILINX_VIVADO": "/opt/Xilinx/Vivado/2024.2",
        "PATH": "/opt/Xilinx/Vivado/2024.2/bin:/usr/bin:/bin",
    },
)

toolchain(
    name = "vivado_toolchain_2024_2",
    exec_compatible_with = ["@rules_vivado//vivado/constraints/version:2024.2"],
    toolchain = ":vivado_2024_2",
    toolchain_type = "@rules_vivado//vivado:toolchain_type",
)

platform(
    name = "vivado_2024_2_platform",
    constraint_values = ["@rules_vivado//vivado/constraints/version:2024.2"],
    exec_properties = {
        "container-image": "docker://your.registry/vivado:2024.2",
    },
    parents = ["@platforms//host"],
)
```

Register both the toolchain and the platform from `MODULE.bazel`:

```starlark
register_toolchains("//tools/vivado:vivado_toolchain_2024_2")
register_execution_platforms("//tools/vivado:vivado_2024_2_platform")
```

The first registered exec platform becomes the default. Switch versions per
build with `--platforms=//tools/vivado:vivado_2024_2_platform` (which also lets
`target_compatible_with = ["@rules_vivado//vivado/constraints/version:2024.2"]`
on a target evaluate against the right constraint), or use a wrapper rule with
`cfg = transition(...)` to switch per target. See
`//tests/transition.bzl` for an example `with_vivado_version` wrapper.
"""

TOOLCHAIN_TYPE = str(Label("//vivado:toolchain_type"))

VivadoToolchainInfo = provider(
    doc = "Toolchain info for the Xilinx Vivado tool.",
    fields = {
        "env": "dict[str, str]: environment variables passed to every Vivado action.",
        "requires_network": "bool: whether Vivado actions need network access (typically for a network license server).",
        "version": "str: The version of Vivado associated with this toolchain.",
        "xilinx_env": (
            "File or None: optional shell script sourced inside the action " +
            "shell immediately before `vivado` runs. Escape hatch for " +
            "shell-side env composition `env` cannot express."
        ),
    },
)

def _vivado_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            vivado_info = VivadoToolchainInfo(
                xilinx_env = ctx.file.xilinx_env,
                requires_network = ctx.attr.requires_network,
                env = ctx.attr.env,
                version = ctx.attr.version,
            ),
        ),
    ]

vivado_toolchain = rule(
    doc = """Declares a Vivado toolchain.

Wrap with `toolchain(...)` and register via `register_toolchains(...)` in
MODULE.bazel so every `vivado_*` rule resolves it automatically. Multiple
instances can be registered side-by-side and selected via `target_settings`
(flag-driven) or `exec_compatible_with` (platform-driven). See the
`//vivado:toolchain.bzl` module docstring and the rules_vivado README for full
walkthroughs.
""",
    implementation = _vivado_toolchain_impl,
    attrs = {
        "env": attr.string_dict(
            doc = "Environment variables passed to every Vivado action.",
            default = {},
        ),
        "requires_network": attr.bool(
            doc = ("Whether Vivado actions need network access. True (the " +
                   "default) is correct for a floating/network license server " +
                   "(`XILINXD_LICENSE_FILE=PORT@HOST`). Set to False for " +
                   "license-free editions (Vivado ML Standard / WebPACK) or " +
                   "node-locked .lic files read from disk. Controls whether " +
                   "the `requires-network` execution requirement is set on " +
                   "every `vivado_*` action."),
            default = True,
        ),
        "version": attr.string(
            doc = "The version of Vivado associated with this toolchain.",
        ),
        "xilinx_env": attr.label(
            doc = ("Optional escape hatch — a shell script sourced inside " +
                   "the action shell immediately before `vivado` runs, for " +
                   "shell-side env composition `env` cannot express. Prefer " +
                   "`env`."),
            allow_single_file = [".sh"],
        ),
    },
)
