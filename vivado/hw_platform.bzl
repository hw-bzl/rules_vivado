"""# vivado_hw_platform rule."""

load(
    "//vivado:providers.bzl",
    "VivadoHwPlatformInfo",
    "VivadoLogInfo",
    "VivadoRoutingCheckpointInfo",
)
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "run_tcl_template",
    "tcl_args",
    "validate_args",
)

def _vivado_hw_platform_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    xsa = ctx.actions.declare_file("{}.xsa".format(ctx.label.name))

    upstream = ctx.attr.checkpoint[VivadoRoutingCheckpointInfo]
    checkpoint_in = upstream.checkpoint
    project_info = getattr(upstream, "project_info", None)

    validate_args(
        ctx.label,
        "write_args",
        ctx.attr.write_args,
        ["-file", "-force", "-fixed", "-hw_only", "-include_bit"],
    )

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{HW_ONLY}}": "1" if ctx.attr.hw_only else "0",
        "{{INCLUDE_BIT}}": "1" if ctx.attr.include_bit else "0",
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{WRITE_ARGS}}": tcl_args(ctx.attr.write_args),
        "{{XSA_PATH}}": xsa.path,
    }

    # A routed `.dcp` is self-contained: the template only
    # `open_checkpoint`s it, so the upstream HDL / IP / BD closure stays
    # out of the action (see `VivadoRoutingCheckpointInfo.input_files`).
    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.write_hw_platform_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = [xsa],
        mnemonic = "VivadoWriteHwPlatform",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream_logs = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream_logs.logs)
    journals = dict(upstream_logs.journals)
    logs["write_hw_platform"] = result.log
    journals["write_hw_platform"] = result.journal

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoHwPlatformInfo(
            xsa = xsa,
            project_info = project_info,
            tcl = result.vivado_tcl,
        ),
        VivadoLogInfo(logs = logs, journals = journals),
        OutputGroupInfo(
            log = depset(logs.values()),
            tcl = depset([result.vivado_tcl]),
            xsa = depset([xsa]),
        ),
    ]

vivado_hw_platform = rule(
    doc = """Write a Xilinx `.xsa` hardware-platform archive from a routed \
checkpoint via `write_hw_platform`.

The `.xsa` is the handoff artifact for Vitis, PetaLinux, and the rest of
the Xilinx SDK tooling. Compose this directly on `vivado_routing` (or
any `VivadoRoutingCheckpointInfo` provider) so `.xsa` production is its
own target, independent of whether a bitstream or device image is also
being built.

Provides `VivadoHwPlatformInfo`.
""",
    implementation = _vivado_hw_platform_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Routed checkpoint the platform is written from.",
            providers = [VivadoRoutingCheckpointInfo],
            mandatory = True,
        ),
        "hw_only": attr.bool(
            doc = ("Pass `-hw_only` to `write_hw_platform`. When True, " +
                   "produces a hardware-only platform (no bitstream " +
                   "embedded); overrides `include_bit`."),
            default = False,
        ),
        "include_bit": attr.bool(
            doc = ("Embed a bitstream in the `.xsa` (`-include_bit`). " +
                   "`write_hw_platform` can only embed a bitstream written " +
                   "in the same Vivado session, so the action first runs " +
                   "`write_bitstream` on the opened checkpoint — a full " +
                   "bitstream generation, with no `timing_check` gate — and " +
                   "then packs the result. Set False to skip that cost when " +
                   "the `.xsa` only needs the hardware description, or " +
                   "`hw_only = True` for an explicitly hardware-only " +
                   "platform (which overrides this). Default True matches " +
                   "the historical `with_xsa` bolt-on behavior."),
            default = True,
        ),
        "threads": attr.int(
            doc = "Threads passed to `general.maxThreads`.",
            default = 8,
        ),
        "write_args": attr.string_list(
            doc = ("Extra flags passed through to `write_hw_platform`. " +
                   "Cannot contain `-file` (the rule's declared `.xsa` path " +
                   "is the argument), `-force` (always emitted), `-fixed` " +
                   "(always emitted for single-image platforms), " +
                   "`-hw_only` / `-include_bit` (use dedicated attrs)."),
            default = [],
        ),
        "write_hw_platform_template": attr.label(
            doc = "The write_hw_platform tcl template.",
            default = Label("//vivado/private:write_hw_platform.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl` files OR `tcl_binary` targets sourced after " +
                    "`write_hw_platform` completes, in list order."),
        pre_doc = ("`.tcl` files OR `tcl_binary` targets sourced on the " +
                   "opened checkpoint before `write_hw_platform` runs, in " +
                   "list order."),
    ),
    provides = [
        DefaultInfo,
        VivadoHwPlatformInfo,
        VivadoLogInfo,
    ],
)
