"""# Implementation-phase rules: placement, physical optimization, routing."""

load(
    "//vivado:providers.bzl",
    "VivadoLogInfo",
    "VivadoPlacementCheckpointInfo",
    "VivadoReportsInfo",
    "VivadoRoutingCheckpointInfo",
    "VivadoSynthCheckpointInfo",
)
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "reports_data",
    "run_tcl_template",
    "tcl_args",
    "validate_args",
)

_REPORTS_ATTR_DOC = (
    "Report types to run after the phase's main transformation. See " +
    "`vivado_synthesis.reports` for the full API."
)

_PLACEMENT_DEFAULT_REPORTS = ["timing_summary", "utilization"]
_ROUTING_DEFAULT_REPORTS = ["io", "power", "route_status", "timing_summary", "utilization"]

def _vivado_placement_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    placement_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))

    upstream_synth = ctx.attr.checkpoint[VivadoSynthCheckpointInfo]
    checkpoint_in = upstream_synth.checkpoint
    impl_xdc_in = getattr(upstream_synth, "impl_xdc", None)
    module_top = getattr(upstream_synth, "module_top", "") or ""
    part_number = getattr(upstream_synth, "part_number", "") or ""
    project_info = getattr(upstream_synth, "project_info", None)
    upstream_input_files = getattr(upstream_synth, "input_files", None)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    reports = reports_data(ctx, ctx.attr.reports)

    validate_args(ctx.label, "place_args", ctx.attr.place_args, [])

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": placement_checkpoint.path,
        "{{IMPL_XDC_BUNDLE}}": impl_xdc_in.path if impl_xdc_in else "",
        "{{PLACE_ARGS}}": tcl_args(ctx.attr.place_args),
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{REPORT_COMMANDS}}": reports.commands_dict,
        "{{REQUESTED_REPORTS}}": reports.requested,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
    }

    outputs = [placement_checkpoint] + reports.files

    input_files = [checkpoint_in]
    if impl_xdc_in:
        input_files.append(impl_xdc_in)

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.placement_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = outputs,
        mnemonic = "VivadoPlace",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs["place"] = result.log
    journals["place"] = result.journal

    transitive_inputs = [upstream_input_files] if upstream_input_files else []
    checkpoint_input_files = depset(
        direct = [placement_checkpoint],
        transitive = transitive_inputs,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoPlacementCheckpointInfo(
            checkpoint = placement_checkpoint,
            module_top = module_top,
            part_number = part_number,
            project_info = project_info,
            input_files = checkpoint_input_files,
            tcl = result.vivado_tcl,
        ),
        VivadoLogInfo(logs = logs, journals = journals),
        VivadoReportsInfo(reports = reports.file_dict),
        OutputGroupInfo(
            log = depset(logs.values()),
            reports = depset(reports.files),
        ),
    ]

vivado_placement = rule(
    doc = "Run placement on a (synthesis-optimized) checkpoint.",
    implementation = _vivado_placement_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Synthesis checkpoint.",
            providers = [VivadoSynthCheckpointInfo],
            mandatory = True,
        ),
        "place_args": attr.string_list(
            doc = "Extra flags passed through to `place_design`.",
            default = [],
        ),
        "placement_template": attr.label(
            doc = "The placement tcl template",
            default = Label("//vivado/private:placement.tcl.template"),
            allow_single_file = [".template"],
        ),
        "reports": attr.string_list(
            doc = _REPORTS_ATTR_DOC,
            default = _PLACEMENT_DEFAULT_REPORTS,
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `place_design`, in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened checkpoint before `place_design`."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
        VivadoPlacementCheckpointInfo,
        VivadoReportsInfo,
    ],
)

def _vivado_place_optimize_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    placement_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))

    upstream_place = ctx.attr.checkpoint[VivadoPlacementCheckpointInfo]
    checkpoint_in = upstream_place.checkpoint
    module_top = getattr(upstream_place, "module_top", "") or ""
    part_number = getattr(upstream_place, "part_number", "") or ""
    project_info = getattr(upstream_place, "project_info", None)
    upstream_input_files = getattr(upstream_place, "input_files", None)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    reports = reports_data(ctx, ctx.attr.reports)

    validate_args(ctx.label, "phys_opt_args", ctx.attr.phys_opt_args, [])

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": placement_checkpoint.path,
        "{{PHYS_OPT_ARGS}}": tcl_args(ctx.attr.phys_opt_args),
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{REPORT_COMMANDS}}": reports.commands_dict,
        "{{REQUESTED_REPORTS}}": reports.requested,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
    }

    outputs = [placement_checkpoint] + reports.files

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.place_optimize_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoPlaceOpt",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs["place_opt"] = result.log
    journals["place_opt"] = result.journal

    transitive_inputs = [upstream_input_files] if upstream_input_files else []
    checkpoint_input_files = depset(
        direct = [placement_checkpoint],
        transitive = transitive_inputs,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoPlacementCheckpointInfo(
            checkpoint = placement_checkpoint,
            module_top = module_top,
            part_number = part_number,
            project_info = project_info,
            input_files = checkpoint_input_files,
            tcl = result.vivado_tcl,
        ),
        VivadoLogInfo(logs = logs, journals = journals),
        VivadoReportsInfo(reports = reports.file_dict),
        OutputGroupInfo(
            log = depset(logs.values()),
            reports = depset(reports.files),
        ),
    ]

vivado_place_optimize = rule(
    doc = "Run post-placement physical optimization.",
    implementation = _vivado_place_optimize_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Placement checkpoint.",
            providers = [VivadoPlacementCheckpointInfo],
            mandatory = True,
        ),
        "phys_opt_args": attr.string_list(
            doc = "Extra flags passed through to `phys_opt_design`.",
            default = [],
        ),
        "place_optimize_template": attr.label(
            doc = "The placement tcl template",
            default = Label("//vivado/private:place_optimize.tcl.template"),
            allow_single_file = [".template"],
        ),
        "reports": attr.string_list(
            doc = _REPORTS_ATTR_DOC,
            default = _PLACEMENT_DEFAULT_REPORTS,
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `phys_opt_design`, in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened checkpoint before `phys_opt_design`."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
        VivadoPlacementCheckpointInfo,
        VivadoReportsInfo,
    ],
)

def _vivado_routing_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    route_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))

    upstream_place = ctx.attr.checkpoint[VivadoPlacementCheckpointInfo]
    checkpoint_in = upstream_place.checkpoint
    module_top = getattr(upstream_place, "module_top", "") or ""
    part_number = getattr(upstream_place, "part_number", "") or ""
    project_info = getattr(upstream_place, "project_info", None)
    upstream_input_files = getattr(upstream_place, "input_files", None)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    reports = reports_data(ctx, ctx.attr.reports)

    validate_args(ctx.label, "route_args", ctx.attr.route_args, [])

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": route_checkpoint.path,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{REPORT_COMMANDS}}": reports.commands_dict,
        "{{REQUESTED_REPORTS}}": reports.requested,
        "{{ROUTE_ARGS}}": tcl_args(ctx.attr.route_args),
        "{{THREADS}}": "{}".format(ctx.attr.threads),
    }

    outputs = [route_checkpoint] + reports.files

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.route_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoRoute",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs["route"] = result.log
    journals["route"] = result.journal

    transitive_inputs = [upstream_input_files] if upstream_input_files else []
    checkpoint_input_files = depset(
        direct = [route_checkpoint],
        transitive = transitive_inputs,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoRoutingCheckpointInfo(
            checkpoint = route_checkpoint,
            module_top = module_top,
            part_number = part_number,
            project_info = project_info,
            input_files = checkpoint_input_files,
            tcl = result.vivado_tcl,
        ),
        VivadoLogInfo(logs = logs, journals = journals),
        VivadoReportsInfo(reports = reports.file_dict),
        OutputGroupInfo(
            log = depset(logs.values()),
            reports = depset(reports.files),
        ),
    ]

vivado_routing = rule(
    doc = "Run routing on a placement checkpoint.",
    implementation = _vivado_routing_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Placement checkpoint.",
            providers = [VivadoPlacementCheckpointInfo],
            mandatory = True,
        ),
        "reports": attr.string_list(
            doc = _REPORTS_ATTR_DOC,
            default = _ROUTING_DEFAULT_REPORTS,
        ),
        "route_args": attr.string_list(
            doc = "Extra flags passed through to `route_design`.",
            default = [],
        ),
        "route_template": attr.label(
            doc = "The routing tcl template",
            default = Label("//vivado/private:route.tcl.template"),
            allow_single_file = [".template"],
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `route_design`, in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened checkpoint before `route_design`."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
        VivadoReportsInfo,
        VivadoRoutingCheckpointInfo,
    ],
)
