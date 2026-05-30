"""Synthesis-phase rules: vivado_synthesize and vivado_synthesis_optimize."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoIPBlockInfo", "VivadoSynthCheckpointInfo")
load(
    "//vivado/private:common.bzl",
    "OPTIONAL_TOOLCHAIN",
    "XILINX_ENV_ATTR",
    "create_and_synth",
    "run_tcl_template",
)

def _vivado_synthesize_impl(ctx):
    synth_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    timing_summary_report = ctx.actions.declare_file("{}_timing.rpt".format(ctx.label.name))
    util_report = ctx.actions.declare_file("{}_util.rpt".format(ctx.label.name))

    default_info = create_and_synth(
        ctx = ctx,
        with_synth = 1,
        synth_checkpoint = synth_checkpoint,
        timing_summary_report = timing_summary_report,
        util_report = util_report,
        synth_strategy = ctx.attr.synth_strategy,
    )

    return [
        default_info[0],
        VivadoSynthCheckpointInfo(checkpoint = synth_checkpoint),
    ]

vivado_synthesize = rule(
    doc = "Create a Vivado project and run synthesis on it.",
    implementation = _vivado_synthesize_impl,
    toolchains = OPTIONAL_TOOLCHAIN,
    attrs = {
        "create_project_tcl_template": attr.label(
            doc = "The create project tcl template",
            default = Label("//vivado/private:create_project.tcl.template"),
            allow_single_file = [".template"],
        ),
        "ip_blocks": attr.label_list(
            doc = "Ip blocks to include in this design.",
            providers = [VivadoIPBlockInfo],
            default = [],
        ),
        "jobs": attr.int(
            doc = "Jobs to pass to vivado which defines the amount of parallelism.",
            default = 4,
        ),
        "module": attr.label(
            doc = "The top level build.",
            providers = [[VerilogInfo], [VhdlInfo]],
            mandatory = True,
        ),
        "module_top": attr.string(
            doc = "The name of the top level verilog module.",
            mandatory = True,
        ),
        "part_number": attr.string(
            doc = "The targeted xilinx part.",
            mandatory = True,
        ),
        "synth_strategy": attr.string(
            doc = "The synthesis strategy to use.",
            default = "Vivado Synthesis Defaults",
        ),
    } | XILINX_ENV_ATTR,
    provides = [
        DefaultInfo,
        VivadoSynthCheckpointInfo,
    ],
)

def _vivado_synthesis_optimize_impl(ctx):
    synth_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    timing_summary_report = ctx.actions.declare_file("{}_timing.rpt".format(ctx.label.name))
    util_report = ctx.actions.declare_file("{}_util.rpt".format(ctx.label.name))
    drc_report = ctx.actions.declare_file("{}_drc.rpt".format(ctx.label.name))
    if ctx.attr.with_probes:
        probes_file = ctx.actions.declare_file("{}.ltx".format(ctx.label.name))
        probes_file_path = probes_file.path
    else:
        probes_file = None
        probes_file_path = ""

    checkpoint_in = ctx.attr.checkpoint[VivadoSynthCheckpointInfo].checkpoint

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": synth_checkpoint.path,
        "{{DRC_REPORT}}": drc_report.path,
        "{{OPT_DIRECTIVE}}": ctx.attr.opt_directive,
        "{{PROBES_FILE}}": probes_file_path,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_REPORT}}": timing_summary_report.path,
        "{{UTIL_REPORT}}": util_report.path,
    }

    outputs = [synth_checkpoint, timing_summary_report, util_report, drc_report]
    if ctx.attr.with_probes:
        outputs.append(probes_file)

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.synthesis_optimize_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoSynthOpt",
        jobs = ctx.attr.threads,
    )

    return [
        default_info[0],
        VivadoSynthCheckpointInfo(checkpoint = synth_checkpoint),
    ]

vivado_synthesis_optimize = rule(
    doc = "Run post-synthesis optimization on a synthesis checkpoint.",
    implementation = _vivado_synthesis_optimize_impl,
    toolchains = OPTIONAL_TOOLCHAIN,
    attrs = {
        "checkpoint": attr.label(
            doc = "Synthesis checkpoint.",
            providers = [VivadoSynthCheckpointInfo],
            mandatory = True,
        ),
        "opt_directive": attr.string(
            doc = "The optimization directive.",
            default = "Explore",
        ),
        "synthesis_optimize_template": attr.label(
            doc = "The synthesis optimization tcl template",
            default = Label("//vivado/private:synth_optimize.tcl.template"),
            allow_single_file = [".template"],
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
        "with_probes": attr.bool(
            doc = "Create debug probes.",
            default = False,
        ),
    } | XILINX_ENV_ATTR,
    provides = [
        DefaultInfo,
        VivadoSynthCheckpointInfo,
    ],
)
