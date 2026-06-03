"""Block-design rule: vivado_block_design."""

load("//vivado:providers.bzl", "VivadoBlockDesignInfo", "VivadoIPBlockInfo")
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "ip_blocks_data",
    "project_hooks_attr",
    "run_tcl_template",
    "tcl_script_attr",
    "tcl_script_data",
)

def _vivado_block_design_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    bd_dir = ctx.actions.declare_directory(ctx.label.name)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks, script = ctx.attr.script[0])
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    ip = ip_blocks_data(ctx.attr.ip_blocks)
    script = tcl_script_data(ctx.attr.script[0])

    substitutions = {
        "{{BD_DIR}}": bd_dir.path,
        "{{BD_SCRIPT}}": script.path,
        "{{IP_CONFIGURED_INSTANCES}}": ip.ip_configured_instances,
        "{{IP_INSTANCES}}": ip.ip_instances,
        "{{IP_REPOS}}": ip.ip_repos,
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
    }

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.block_design_template,
        substitutions = substitutions,
        input_files = ip.input_files,
        output_files = [bd_dir],
        mnemonic = "VivadoBlockDesign",
        jobs = ctx.attr.jobs,
        tools = pre.tools + post.tools + script.tools,
    )

    return [
        DefaultInfo(
            files = depset(result.outputs),
        ),
        VivadoBlockDesignInfo(
            bd_dir = bd_dir,
            ip_block_repos = ip.input_files,
            module_top = ctx.attr.module_top,
            # `project_hooks` don't fire in THIS BD's Vivado action; they
            # contribute to any downstream `vivado_project` that folds
            # this BD in via `block_designs`. The project's impl passes
            # the merged Target list through `hook_invocation`.
            project_hooks = ctx.attr.project_hooks,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["ip_blocks"],
        ),
    ]

vivado_block_design = rule(
    doc = """Build a Vivado block design (.bd) from a user-authored Tcl script.

`script` is sourced inside a fresh Vivado project. It must call
`create_bd_design "<module_top>"`, add/connect cells, and end with
`save_bd_design`. The attr takes an executable target — in practice a
`tcl_binary`, which is what carries the `deps` a script needs to
`package require` shared `tcl_library` helpers. An extra-toolchains
transition routes it through the Vivado tcl toolchain, so its wrapper
comes out as a `.vhook.tcl` Vivado can source directly and its deps land
on `auto_path`.

The resulting `.bd` is normalized to `<bd_dir>/<module_top>.bd` so
consumers can reference it predictably.

Use the `block_designs` attribute on `vivado_project` to fold this BD
into a synth project; `vivado_synthesis` picks it up and runs
`generate_target {synthesis implementation}` on it automatically.

Block designs may reference packaged IP via the `ip_blocks` attribute; those
IP repos are propagated to consumers so the synth project's IP catalog
resolves the same `create_ip` calls baked into the BD.
""",
    implementation = _vivado_block_design_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "block_design_template": attr.label(
            doc = "The create-bd tcl template.",
            default = Label("//vivado/private:create_bd.tcl.template"),
            allow_single_file = [".template"],
        ),
        "ip_blocks": attr.label_list(
            doc = "Packaged IP blocks referenced by the BD's `create_bd_cell` calls.",
            providers = [VivadoIPBlockInfo],
            default = [],
        ),
        "jobs": attr.int(
            doc = "Jobs to pass to vivado (resource hint to Bazel's scheduler).",
            default = 1,
        ),
        "module_top": attr.string(
            doc = "Name passed to `create_bd_design` in `script`. Used to locate the produced `.bd`.",
            mandatory = True,
        ),
        "part_number": attr.string(
            doc = "Xilinx part number the BD is generated for.",
            mandatory = True,
        ),
        "project_hooks": project_hooks_attr(),
        "script": tcl_script_attr(
            doc = ("Executable target (a `tcl_binary`) whose script is " +
                   "sourced inside a fresh Vivado project to build the " +
                   "block design. Must call `create_bd_design " +
                   "\"<module_top>\"` and end with `save_bd_design`. Its " +
                   "`tcl_library` deps are staged as runfiles and reached " +
                   "with `package require`. A bare `.tcl` file is not " +
                   "accepted; wrap it in a `tcl_binary`."),
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `generate_target all`, before the " +
                    "project closes. Sourced in list order. Useful for " +
                    "`make_wrapper` (auto-generated HDL wrapper) or " +
                    "`write_bd_tcl` round-tripping."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced after project + IP-block setup, before sourcing " +
                   "the user's BD TCL. Sourced in list order."),
    ),
    provides = [
        DefaultInfo,
        VivadoBlockDesignInfo,
    ],
)
