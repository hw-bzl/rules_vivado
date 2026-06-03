"""Pre-packaged IP rule: vivado_packaged_ip."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoIPBlockInfo")
load("//vivado:toolchain.bzl", "TOOLCHAIN_TYPE")
load("//vivado/private:common.bzl", "hdl_sources_data")

def _stage_relpath(short_path, package, strip_prefix):
    """Compute where `short_path` should land in the staged TreeArtifact.

    Handles both main-repo (`<package>/<sub>`) and external-repo
    (`../<repo_name>/<package>/<sub>`) `short_path` shapes.
    """
    parts = short_path.split("/")
    pkg_parts = package.split("/") if package else []

    rel_parts = None
    if pkg_parts:
        for i in range(len(parts) - len(pkg_parts) + 1):
            if parts[i:i + len(pkg_parts)] == pkg_parts:
                rel_parts = parts[i + len(pkg_parts):]
                break
    elif parts[:1] == [".."] and len(parts) >= 2:
        rel_parts = parts[2:]
    else:
        rel_parts = parts

    if rel_parts == None:
        rel_parts = [parts[-1]]

    if strip_prefix:
        strip_parts = strip_prefix.strip("/").split("/")
        if rel_parts[:len(strip_parts)] == strip_parts:
            rel_parts = rel_parts[len(strip_parts):]

    return "/".join(rel_parts)

def _vivado_packaged_ip_impl(ctx):
    out_dir = ctx.actions.declare_directory(ctx.label.name)
    package = ctx.label.package

    hdl_files = []
    for lib in ctx.attr.hdl_libraries:
        hdl_files.extend(hdl_sources_data(lib).all_files)
    all_input_files = ctx.files.srcs + hdl_files

    if not all_input_files:
        fail(
            ("{label}: vivado_packaged_ip needs at least one of `srcs` or " +
             "`hdl_libraries` to be non-empty.").format(label = ctx.label),
        )

    entries = []
    for f in all_input_files:
        rel = _stage_relpath(f.short_path, package, ctx.attr.strip_prefix)
        entries.append((f.path, rel))

    # `cp -L` dereferences symlinks so the staged tree contains real files,
    # not chains back to source.
    cmd_lines = ["mkdir -p " + out_dir.path]
    seen_dirs = {}
    for src, dst in entries:
        full_dst = out_dir.path + "/" + dst if dst else out_dir.path + "/" + src.rsplit("/", 1)[-1]
        if "/" in dst:
            dst_dir = out_dir.path + "/" + dst.rsplit("/", 1)[0]
        else:
            dst_dir = out_dir.path
        if dst_dir not in seen_dirs:
            cmd_lines.append("mkdir -p " + dst_dir)
            seen_dirs[dst_dir] = True
        cmd_lines.append("cp -L {} {}".format(src, full_dst))

    ctx.actions.run_shell(
        outputs = [out_dir],
        inputs = all_input_files,
        command = " && ".join(cmd_lines),
        progress_message = "Staging packaged IP repo: %{label}",
        mnemonic = "VivadoPackagedIp",
        toolchain = TOOLCHAIN_TYPE,
        env = ctx.toolchains[TOOLCHAIN_TYPE].vivado_info.env,
    )

    return [
        DefaultInfo(files = depset([out_dir])),
        VivadoIPBlockInfo(
            repo = [out_dir],
            configured_instance = None,
            instantiable = None,
            project_hooks = [],
        ),
    ]

vivado_packaged_ip = rule(
    doc = """Wrap a pre-packaged Vivado IP directory as a consumable IP repo.

For third-party / vendor-supplied IPs — a tree rooted at one or more
`component.xml` files. For Xilinx-catalog IPs configured via a
`create_ip` Tcl use `vivado_xci`; for your own HDL packaged as new IP
use `vivado_ip_core`.

Stages each file in `srcs` into a TreeArtifact, preserving its path
relative to the rule's package (with optional `strip_prefix` applied), and
exposes the staged directory via `VivadoIPBlockInfo.repo`. Consumers list
the target in their `ip_blocks` attr; the existing IP-block plumbing adds
the directory to `ip_repo_paths` in the consumer's project so any
`create_ip` calls referencing the IP's VLNV resolve via the catalog.

The rule is repository-agnostic: it works identically in the main repo,
inside an `http_archive`-fetched external repo, or in any custom
repository rule's generated BUILD file.
""",
    implementation = _vivado_packaged_ip_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "hdl_libraries": attr.label_list(
            doc = "HDL libraries whose transitive sources contribute to the staged IP tree. Walks `VhdlInfo` / `VerilogInfo` providers and stages each `File` at its package-relative path under the staged root (same path computation as `srcs`).",
            providers = [[VerilogInfo], [VhdlInfo]],
            allow_empty = True,
        ),
        "srcs": attr.label_list(
            doc = "Files under the IP repo root — typically the non-HDL portion: `component.xml`, `xgui/**`, vendor TCL scripts.",
            allow_files = True,
        ),
        "strip_prefix": attr.string(
            doc = "Optional package-relative prefix to strip from each src's staging path. Mirrors `http_archive.strip_prefix` semantics. Use when the BUILD file is at a higher level than the IP repo root and you want a flatter staged tree. Vivado walks `ip_repo_paths` recursively for `component.xml`, so this is hygiene/predictability only — leaving it empty doesn't affect correctness.",
            default = "",
        ),
    },
    provides = [
        DefaultInfo,
        VivadoIPBlockInfo,
    ],
)
