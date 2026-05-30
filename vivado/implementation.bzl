"""Implementation-phase rules: placement, physical optimization, routing."""

load(
    "//vivado:providers.bzl",
    "VivadoPlacementCheckpointInfo",
    "VivadoRoutingCheckpointInfo",
    "VivadoSynthCheckpointInfo",
)
load(
    "//vivado/private:common.bzl",
    "OPTIONAL_TOOLCHAIN",
    "XILINX_ENV_ATTR",
    "run_tcl_template",
)

def _vivado_placement_impl(ctx):
    placement_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    timing_summary_report = ctx.actions.declare_file("{}_timing.rpt".format(ctx.label.name))
    util_report = ctx.actions.declare_file("{}_util.rpt".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoSynthCheckpointInfo].checkpoint

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": placement_checkpoint.path,
        "{{PLACEMENT_DIRECTIVE}}": ctx.attr.placement_directive,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_REPORT}}": timing_summary_report.path,
        "{{UTIL_REPORT}}": util_report.path,
    }

    outputs = [placement_checkpoint, timing_summary_report, util_report]

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.placement_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoPlace",
        jobs = ctx.attr.threads,
    )

    return [
        default_info[0],
        VivadoPlacementCheckpointInfo(checkpoint = placement_checkpoint),
    ]

vivado_placement = rule(
    doc = "Run placement on a (synthesis-optimized) checkpoint.",
    implementation = _vivado_placement_impl,
    toolchains = OPTIONAL_TOOLCHAIN,
    attrs = {
        "checkpoint": attr.label(
            doc = "Synthesis checkpoint.",
            providers = [VivadoSynthCheckpointInfo],
            mandatory = True,
        ),
        "placement_directive": attr.string(
            doc = "The optimization directive.",
            default = "Explore",
        ),
        "placement_template": attr.label(
            doc = "The placement tcl template",
            default = Label("//vivado/private:placement.tcl.template"),
            allow_single_file = [".template"],
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
    } | XILINX_ENV_ATTR,
    provides = [
        DefaultInfo,
        VivadoPlacementCheckpointInfo,
    ],
)

def _vivado_place_optimize_impl(ctx):
    placement_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    timing_summary_report = ctx.actions.declare_file("{}_timing.rpt".format(ctx.label.name))
    util_report = ctx.actions.declare_file("{}_util.rpt".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoPlacementCheckpointInfo].checkpoint

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": placement_checkpoint.path,
        "{{PHYS_OPT_DIRECTIVE}}": ctx.attr.phys_opt_directive,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_REPORT}}": timing_summary_report.path,
        "{{UTIL_REPORT}}": util_report.path,
    }

    outputs = [placement_checkpoint, timing_summary_report, util_report]

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.place_optimize_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoPlaceOpt",
        jobs = ctx.attr.threads,
    )

    return [
        default_info[0],
        VivadoPlacementCheckpointInfo(checkpoint = placement_checkpoint),
    ]

vivado_place_optimize = rule(
    doc = "Run post-placement physical optimization.",
    implementation = _vivado_place_optimize_impl,
    toolchains = OPTIONAL_TOOLCHAIN,
    attrs = {
        "checkpoint": attr.label(
            doc = "Placement checkpoint.",
            providers = [VivadoPlacementCheckpointInfo],
            mandatory = True,
        ),
        "phys_opt_directive": attr.string(
            doc = "The optimization directive.",
            default = "AggressiveExplore",
        ),
        "place_optimize_template": attr.label(
            doc = "The placement tcl template",
            default = Label("//vivado/private:place_optimize.tcl.template"),
            allow_single_file = [".template"],
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
    } | XILINX_ENV_ATTR,
    provides = [
        DefaultInfo,
        VivadoPlacementCheckpointInfo,
    ],
)

def _vivado_routing_impl(ctx):
    route_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    timing_summary_report = ctx.actions.declare_file("{}_timing.rpt".format(ctx.label.name))
    util_report = ctx.actions.declare_file("{}_util.rpt".format(ctx.label.name))
    status_report = ctx.actions.declare_file("{}_status.rpt".format(ctx.label.name))
    io_report = ctx.actions.declare_file("{}_io.rpt".format(ctx.label.name))
    power_report = ctx.actions.declare_file("{}_power.rpt".format(ctx.label.name))
    design_analysis_report = ctx.actions.declare_file("{}_design_analysis.rpt".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoPlacementCheckpointInfo].checkpoint

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": route_checkpoint.path,
        "{{DESIGN_ANALYSIS_REPORT}}": design_analysis_report.path,
        "{{IO_REPORT}}": io_report.path,
        "{{POWER_REPORT}}": power_report.path,
        "{{ROUTE_DIRECTIVE}}": ctx.attr.route_directive,
        "{{STATUS_REPORT}}": status_report.path,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_REPORT}}": timing_summary_report.path,
        "{{UTIL_REPORT}}": util_report.path,
    }

    outputs = [
        route_checkpoint,
        timing_summary_report,
        util_report,
        status_report,
        io_report,
        power_report,
        design_analysis_report,
    ]

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.route_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoRoute",
        jobs = ctx.attr.threads,
    )

    return [
        default_info[0],
        VivadoRoutingCheckpointInfo(checkpoint = route_checkpoint),
    ]

vivado_routing = rule(
    doc = "Run routing on a placement checkpoint.",
    implementation = _vivado_routing_impl,
    toolchains = OPTIONAL_TOOLCHAIN,
    attrs = {
        "checkpoint": attr.label(
            doc = "Placement checkpoint.",
            providers = [VivadoPlacementCheckpointInfo],
            mandatory = True,
        ),
        "route_directive": attr.string(
            doc = "The routing directive.",
            default = "Explore",
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
    } | XILINX_ENV_ATTR,
    provides = [
        DefaultInfo,
        VivadoRoutingCheckpointInfo,
    ],
)
