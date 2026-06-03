"""# Toolchain for the Xilinx Vivado tool."""

TOOLCHAIN_TYPE = str(Label("//vivado:toolchain_type"))

def _vivado_toolchain_info_init(
        *,
        vivado,
        env = {},
        requires_network = True,
        resources = {},
        sanitizer = None,
        version = "",
        xilinx_env = None):
    """Supply defaults so a third-party toolchain rule can omit optional fields.

    Every field but `vivado` has a default. New fields get one here so
    adding them never breaks an existing `VivadoToolchainInfo(...)` call
    outside this repo.
    """
    return {
        "env": env,
        "requires_network": requires_network,
        "resources": resources,
        "sanitizer": sanitizer,
        "version": version,
        "vivado": vivado,
        "xilinx_env": xilinx_env,
    }

VivadoToolchainInfo, _new_vivado_toolchain_info = provider(
    doc = ("Toolchain info for the Xilinx Vivado tool. Only `vivado` is " +
           "required; every other field has a default so toolchain rules " +
           "outside this repo keep working when fields are added."),
    fields = {
        "env": "dict[str, str]: environment variables passed to every Vivado action. Default `{}`.",
        "requires_network": "bool: whether Vivado actions need network access (typically for a network license server). Default `True`.",
        "resources": "dict[str, str]: optional `--local_resources` slots every Vivado action claims (values are counts as strings). Each entry becomes an `execution_requirements[\"resources:<name>\"] = <count>` on every action, so users can serialize Vivado runs against arbitrary budgets they've declared via `--local_resources=<name>=<total>` (e.g. license seats, container concurrency). Empty by default — actions schedule freely against `cpu` / `memory` only.",
        "sanitizer": "FilesToRunProvider or None: executable invoked from every Vivado action's EXIT trap to rewrite the sandbox-root prefix in declared outputs. `vivado_toolchain` wires in the bundled default; `None` (the constructor default) leaves outputs unsanitized, which still builds but caches less well across hosts.",
        "version": "str: The version of Vivado associated with this toolchain. Default `\"\"`.",
        "vivado": "FilesToRunProvider: executable Bazel invokes for every Vivado action. Typically a shim that `exec`s the real `vivado` binary. Required.",
        "xilinx_env": "File or None: optional shell script sourced immediately before `vivado` runs, for shell-side env composition `env` cannot express. Default `None`.",
    },
    init = _vivado_toolchain_info_init,
)

def _vivado_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            vivado_info = VivadoToolchainInfo(
                vivado = ctx.attr.vivado[DefaultInfo].files_to_run,
                xilinx_env = ctx.file.xilinx_env,
                requires_network = ctx.attr.requires_network,
                env = ctx.attr.env,
                resources = ctx.attr.resources,
                sanitizer = ctx.attr.sanitizer[DefaultInfo].files_to_run,
                version = ctx.attr.version,
            ),
        ),
    ]

vivado_toolchain = rule(
    doc = """Declares a Vivado toolchain.

Wrap it with `toolchain(...)` and register that via
`register_toolchains(...)` in MODULE.bazel; every `vivado_*` rule then
resolves the Xilinx environment automatically, with no per-target
`xilinx_env` to thread through. Registering one is required.

Multiple instances can be registered side-by-side and selected via
`target_settings` (flag-driven) or `exec_compatible_with`
(platform-driven) — the latter against the per-version `constraint_value`s
in `//vivado/constraints/version`.

Emits `VivadoToolchainInfo` on `ToolchainInfo.vivado_info`.
""",
    implementation = _vivado_toolchain_impl,
    attrs = {
        "env": attr.string_dict(
            doc = "Environment variables passed to every Vivado action.",
            default = {},
        ),
        "requires_network": attr.bool(
            doc = ("Sets the `requires-network` execution requirement on " +
                   "every `vivado_*` action. True (the default) is correct " +
                   "for a floating license server " +
                   "(`XILINXD_LICENSE_FILE=PORT@HOST`); set it False for " +
                   "license-free editions (Vivado ML Standard / WebPACK) " +
                   "or node-locked `.lic` files read from disk."),
            default = True,
        ),
        "resources": attr.string_dict(
            doc = ("`--local_resources` slots every Vivado action claims: " +
                   "resource name -> per-action count (as a string). Each " +
                   "entry becomes " +
                   "`execution_requirements[\"resources:<name>\"] = <count>`, " +
                   "letting you serialize Vivado runs against a budget " +
                   "declared with `--local_resources=<name>=<total>` — " +
                   "license seats, container concurrency, whatever. " +
                   "`{\"vivado_license\": \"1\"}` is the common case. Every " +
                   "name used here needs a matching `--local_resources` " +
                   "registration or actions fail to schedule. Empty by " +
                   "default, so actions schedule freely."),
            default = {},
        ),
        "sanitizer": attr.label(
            doc = ("Executable called from every Vivado action's EXIT trap " +
                   "to rewrite the sandbox-root prefix baked into declared " +
                   "outputs with the fixed marker `<execroot>/`. That makes " +
                   "outputs byte-identical across hosts, sandbox " +
                   "strategies, and RBE-worker sandbox UUIDs, so caches hit " +
                   "and shipped artifacts don't leak a worker's path.\n\n" +
                   "Invoked as `<sanitizer> <sandbox_root> <marker> " +
                   "<path>...`, where each path is a declared output — a " +
                   "file, or a TreeArtifact directory to walk. Its exit " +
                   "status is ignored: sanitization must never fail an " +
                   "otherwise-successful Vivado run.\n\n" +
                   "Built for the exec platform and staged with its " +
                   "runfiles, so any `*_binary` works; the default is a " +
                   "`sh_binary` doing a `sed` sweep that skips known binary " +
                   "formats. Override only for custom semantics."),
            default = Label("//vivado/private:sanitize_paths"),
            executable = True,
            cfg = "exec",
        ),
        "version": attr.string(
            doc = "The version of Vivado associated with this toolchain.",
        ),
        "vivado": attr.label(
            doc = ("The Vivado executable. Typically a small bash shim that " +
                   "`exec`s the real `vivado` out of a known install path " +
                   "(e.g. baked into a container image), but any " +
                   "`*_binary` rule works too — runfiles travel along. " +
                   "Defaults to a stock shim that calls `vivado` from the " +
                   "exec platform's `PATH` as a migration aid; production " +
                   "toolchains should pin the install path with their own " +
                   "shim."),
            default = Label("//vivado/private:vivado.sh"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "xilinx_env": attr.label(
            doc = ("Optional escape hatch — a shell script sourced inside " +
                   "the action shell immediately before `vivado` runs, for " +
                   "shell-side env composition `env` cannot express. " +
                   "Prefer `env`. `vivado_xsim_test` also sources it at " +
                   "test time to put `xvlog` / `xelab` / `xsim` on `PATH`."),
            allow_single_file = True,
        ),
    },
)
