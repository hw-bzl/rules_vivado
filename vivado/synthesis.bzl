"""# Synthesis-phase rules: vivado_synthesis and vivado_synthesis_optimize."""

load(
    "//vivado:providers.bzl",
    "VivadoLogInfo",
    "VivadoProjectInfo",
    "VivadoReportsInfo",
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

# Phase-name slugs keying `VivadoLogInfo.{logs,journals}`.
_PHASE_SYNTH = "synth"
_PHASE_SYNTH_OPT = "synth_opt"

_SYNTH_DEFAULT_REPORTS = ["timing_summary", "utilization"]
_SYNTH_OPT_DEFAULT_REPORTS = ["drc", "timing_summary", "utilization"]

def _vivado_synthesis_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    if (ctx.attr.synth_invocation == "launch_runs" and
        ctx.attr.project_mode == "in_memory"):
        fail(("vivado_synthesis {}: `synth_invocation = \"launch_runs\"` " +
              "requires `project_mode = \"project\"` (Vivado's managed-run " +
              "infrastructure is unavailable in `create_project -in_memory` " +
              "mode). Use `synth_invocation = \"synth_design\"` for the " +
              "`in_memory` flow.").format(ctx.label))

    project_info = ctx.attr.project[VivadoProjectInfo]

    validate_args(ctx.label, "synth_args", ctx.attr.synth_args, ["-top"])

    synth_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))
    impl_xdc_bundle = ctx.actions.declare_file("{}.impl.xdc".format(ctx.label.name))

    reports = reports_data(ctx, ctx.attr.reports)

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    project_mode = ctx.attr.project_mode
    if project_mode == "project":
        project_dir = ctx.actions.declare_directory(ctx.label.name)
        project_dir_path = project_dir.path
    else:
        # In-memory mode declares no on-disk project tree; PROJECT_DIR still
        # needs a value for the emitted script's `imported_bds` / `imported_xcis`
        # sibling copies, so we point it at CWD.
        project_dir = None
        project_dir_path = "."

    outputs = [synth_checkpoint, impl_xdc_bundle] + reports.files
    if project_dir != None:
        outputs.append(project_dir)

    substitutions = {
        "{{IMPL_XDC_BUNDLE}}": impl_xdc_bundle.path,
        "{{JOBS}}": "{}".format(ctx.attr.jobs),
        "{{MODULE_TOP}}": project_info.module_top,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{PROJECT_DIR}}": project_dir_path,
        "{{PROJECT_MODE}}": project_mode,
        "{{PROJECT_TCL}}": project_info.project_tcl.path,
        "{{REPORT_COMMANDS}}": reports.commands_dict,
        "{{REQUESTED_REPORTS}}": reports.requested,
        "{{SYNTH_ARGS}}": tcl_args(ctx.attr.synth_args),
        "{{SYNTH_CHECKPOINT}}": synth_checkpoint.path,
        "{{SYNTH_INVOCATION}}": ctx.attr.synth_invocation,
        "{{SYNTH_STRATEGY}}": ctx.attr.synth_strategy,
    }

    input_files = (
        [project_info.project_tcl] + project_info.input_files.to_list()
    )

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.synthesis_tcl_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = outputs,
        mnemonic = "VivadoSynth",
        jobs = ctx.attr.jobs,
        tools = project_info.hook_tools + pre.tools + post.tools,
    )

    logs = {_PHASE_SYNTH: result.log}
    journals = {_PHASE_SYNTH: result.journal}

    # Everything a downstream `read_checkpoint` action needs to open this
    # checkpoint hermetically: the upstream project's input closure, this
    # phase's checkpoint file, and the impl-XDC bundle.
    checkpoint_input_files = depset(
        direct = [synth_checkpoint, impl_xdc_bundle],
        transitive = [project_info.input_files],
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoSynthCheckpointInfo(
            checkpoint = synth_checkpoint,
            impl_xdc = impl_xdc_bundle,
            module_top = project_info.module_top,
            part_number = project_info.part_number,
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

vivado_synthesis = rule(
    doc = ("Run synthesis on a `vivado_project`. Sources the project's " +
           "emitted TCL script inside a single Vivado action, generates " +
           "IP / BD targets (global synthesis — no OOC runs), runs the top " +
           "synth (`launch_runs` or `synth_design`), and writes a `.dcp` " +
           "checkpoint + impl-XDC bundle for downstream implementation " +
           "phases."),
    implementation = _vivado_synthesis_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "jobs": attr.int(
            doc = "Jobs to pass to vivado which defines the amount of parallelism.",
            default = 4,
        ),
        "project": attr.label(
            doc = ("`vivado_project` target carrying the emitted project " +
                   "TCL script + its transitive input closure. All " +
                   "project-shape attrs (module, module_top, part_number, " +
                   "block_designs, ip_blocks, pre_hooks_early, etc.) live " +
                   "on that target, not here."),
            providers = [VivadoProjectInfo],
            mandatory = True,
        ),
        "project_mode": attr.string(
            doc = ("How Vivado stores project state. `project` creates a named " +
                   "on-disk project so managed-run infrastructure " +
                   "(`launch_runs`, `synth_1`) is available. `in_memory` calls " +
                   "`create_project -in_memory`; managed runs are unavailable, " +
                   "so `synth_invocation = launch_runs` requires `project`. " +
                   "The two modes can produce different netlist hierarchies for " +
                   "block-design-instantiated IPs, affecting downstream " +
                   "physical constraints that target IP-internal cells/nets."),
            default = "project",
            values = [
                "in_memory",
                "project",
            ],
        ),
        "reports": attr.string_list(
            doc = ("Report types to run after `synth_design`, before checkpoint " +
                   "write. Each entry must be a key in `REPORT_TYPES` " +
                   "(`vivado/private/common.bzl`). Reports live at " +
                   "`<target>.reports/<filename>` and are wrapped in `catch` so " +
                   "a single failure writes an empty file rather than aborting. " +
                   "Pass `reports = []` to disable."),
            default = _SYNTH_DEFAULT_REPORTS,
        ),
        "synth_args": attr.string_list(
            doc = ("Extra flags for `synth_design` in the `synth_design` " +
                   "invocation path. Cannot contain `-top` (the rule emits that " +
                   "from the project's `module_top`). Not consulted on the " +
                   "`launch_runs` path; there, set `STEPS.SYNTH_DESIGN.ARGS.*` " +
                   "run properties from a `pre_hooks` script."),
            default = [],
        ),
        "synth_invocation": attr.string(
            doc = ("How `synth_design` is invoked. `launch_runs` wraps it in a " +
                   "managed `synth_1` design-run (fresh Vivado process re-loads " +
                   "project state from disk). `synth_design` invokes it in the " +
                   "same process. Multi-config XCI consumer instantiations " +
                   "require `synth_design`: in `launch_runs` the re-loading " +
                   "process binds consumer wrappers to the IP's project-managed " +
                   "synth wrapper (which doesn't propagate consumer-side " +
                   "generics), so wrappers passing distinct generic combinations " +
                   "surface as `__parameterized<N>` black boxes."),
            default = "launch_runs",
            values = [
                "launch_runs",
                "synth_design",
            ],
        ),
        "synth_strategy": attr.string(
            doc = "The synthesis strategy to use.",
            default = "Vivado Synthesis Defaults",
        ),
        "synthesis_tcl_template": attr.label(
            doc = "The synthesis tcl template.",
            default = Label("//vivado/private:synthesis.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced on the open synthesized design (after " +
                    "`open_run \"synth_1\"`), before checkpoint write and " +
                    "reports. Sourced in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced after the project script finishes (post " +
                   "`generate_target`) but before synth runs are launched. " +
                   "Sourced in list order."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
        VivadoReportsInfo,
        VivadoSynthCheckpointInfo,
    ],
)

def _vivado_synthesis_optimize_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    synth_checkpoint = ctx.actions.declare_file("{}.dcp".format(ctx.label.name))

    upstream_synth = ctx.attr.checkpoint[VivadoSynthCheckpointInfo]
    checkpoint_in = upstream_synth.checkpoint
    impl_xdc_in = getattr(upstream_synth, "impl_xdc", None)
    module_top = getattr(upstream_synth, "module_top", "") or ""
    part_number = getattr(upstream_synth, "part_number", "") or ""
    project_info = getattr(upstream_synth, "project_info", None)

    validate_args(ctx.label, "opt_args", ctx.attr.opt_args, [])

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    reports = reports_data(ctx, ctx.attr.reports)

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{CHECKPOINT_OUT}}": synth_checkpoint.path,
        "{{IMPL_XDC_BUNDLE}}": impl_xdc_in.path if impl_xdc_in else "",
        "{{MODULE_TOP}}": module_top,
        "{{OPT_ARGS}}": tcl_args(ctx.attr.opt_args),
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{REPORT_COMMANDS}}": reports.commands_dict,
        "{{REQUESTED_REPORTS}}": reports.requested,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
    }

    outputs = [synth_checkpoint] + reports.files

    input_files = [checkpoint_in]
    if impl_xdc_in:
        input_files.append(impl_xdc_in)

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.synthesis_optimize_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = outputs,
        mnemonic = "VivadoSynthOpt",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs[_PHASE_SYNTH_OPT] = result.log
    journals[_PHASE_SYNTH_OPT] = result.journal

    # Forward the upstream's transitive input closure so a consumer of THIS
    # checkpoint doesn't have to also depend on the pre-opt checkpoint's
    # closure. `synth_checkpoint` (this phase's output) replaces the upstream
    # `.dcp`; the impl-XDC bundle is now baked into the checkpoint so it
    # drops out of the closure.
    upstream_input_files = getattr(upstream_synth, "input_files", None)
    transitive_inputs = [upstream_input_files] if upstream_input_files else []
    checkpoint_input_files = depset(
        direct = [synth_checkpoint],
        transitive = transitive_inputs,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        # `opt_design` baked the impl-xdc bundle (if any) into the checkpoint,
        # so downstream phases don't need to re-read it.
        VivadoSynthCheckpointInfo(
            checkpoint = synth_checkpoint,
            impl_xdc = None,
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

vivado_synthesis_optimize = rule(
    doc = "Run post-synthesis optimization on a synthesis checkpoint.",
    implementation = _vivado_synthesis_optimize_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Synthesis checkpoint.",
            providers = [VivadoSynthCheckpointInfo],
            mandatory = True,
        ),
        "opt_args": attr.string_list(
            doc = "Extra flags passed through to `opt_design`.",
            default = [],
        ),
        "reports": attr.string_list(
            doc = "Report types to run after `opt_design`; see `vivado_synthesis.reports`.",
            default = _SYNTH_OPT_DEFAULT_REPORTS,
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
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `opt_design`, before reports " +
                    "and checkpoint write. Sourced in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened synth checkpoint, " +
                   "before `opt_design`. Sourced in list order."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
        VivadoReportsInfo,
        VivadoSynthCheckpointInfo,
    ],
)
