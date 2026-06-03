"""# vivado_debug_probes rule."""

load(
    "//vivado:providers.bzl",
    "VivadoDebugProbesInfo",
    "VivadoLogInfo",
    "VivadoPlacementCheckpointInfo",
    "VivadoRoutingCheckpointInfo",
    "VivadoSynthCheckpointInfo",
)
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "run_tcl_template",
)

def _resolve_upstream(target):
    """Pick the most-specific checkpoint provider present on `target`.

    Priority: routing > placement > synth. Consumers usually want the
    most-implemented checkpoint available so probes track final physical
    resources, but the rule accepts any phase.
    """
    if VivadoRoutingCheckpointInfo in target:
        return target[VivadoRoutingCheckpointInfo]
    if VivadoPlacementCheckpointInfo in target:
        return target[VivadoPlacementCheckpointInfo]
    return target[VivadoSynthCheckpointInfo]

def _vivado_debug_probes_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    ltx = ctx.actions.declare_file("{}.ltx".format(ctx.label.name))

    upstream = _resolve_upstream(ctx.attr.checkpoint)
    checkpoint_in = upstream.checkpoint
    project_info = getattr(upstream, "project_info", None)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{PROBES_FILE}}": ltx.path,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
    }

    # A `.dcp` is self-contained: the template only `open_checkpoint`s it,
    # so the upstream HDL / IP / BD closure stays out of the action (see
    # `VivadoSynthCheckpointInfo.input_files`).
    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.write_debug_probes_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = [ltx],
        mnemonic = "VivadoWriteDebugProbes",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream_logs = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream_logs.logs)
    journals = dict(upstream_logs.journals)
    logs["write_debug_probes"] = result.log
    journals["write_debug_probes"] = result.journal

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoDebugProbesInfo(
            ltx = ltx,
            project_info = project_info,
            tcl = result.vivado_tcl,
        ),
        VivadoLogInfo(logs = logs, journals = journals),
        OutputGroupInfo(
            log = depset(logs.values()),
            ltx = depset([ltx]),
            tcl = depset([result.vivado_tcl]),
        ),
    ]

vivado_debug_probes = rule(
    doc = """Emit a `.ltx` debug-probes file from a phase checkpoint via \
`write_debug_probes`.

Vivado's Hardware Manager reads the `.ltx` during ILA / VIO bring-up to
map probe nets back to design signals. Any phase checkpoint works, so
point `checkpoint` at whichever phase suits the design — usually
post-place or post-route, since probes track physical resources.

Provides `VivadoDebugProbesInfo`.
""",
    implementation = _vivado_debug_probes_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = ("Phase checkpoint (synth, placement, or routing). Rule " +
                   "picks the most-specific provider present on the target."),
            providers = [
                [VivadoSynthCheckpointInfo],
                [VivadoPlacementCheckpointInfo],
                [VivadoRoutingCheckpointInfo],
            ],
            mandatory = True,
        ),
        "threads": attr.int(
            doc = "Threads passed to `general.maxThreads`.",
            default = 8,
        ),
        "write_debug_probes_template": attr.label(
            doc = "The write_debug_probes tcl template.",
            default = Label("//vivado/private:write_debug_probes.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl` files OR `tcl_binary` targets sourced after " +
                    "`write_debug_probes` completes, in list order."),
        pre_doc = ("`.tcl` files OR `tcl_binary` targets sourced on the " +
                   "opened checkpoint before `write_debug_probes`, in list " +
                   "order."),
    ),
    provides = [
        DefaultInfo,
        VivadoDebugProbesInfo,
        VivadoLogInfo,
    ],
)
