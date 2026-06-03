"""# vivado_project rule."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(
    "//vivado:providers.bzl",
    "VivadoBlockDesignInfo",
    "VivadoIPBlockInfo",
    "VivadoProjectInfo",
)
load(
    "//vivado/private:common.bzl",
    "DEFAULT_HOOK_EXTS",
    "TOOLCHAIN_TYPE",
    "block_designs_data",
    "hdl_sources_data",
    "hook_invocation",
    "ip_blocks_data",
    "merge_project_hook_contributions",
    "tcl_hook_flag_attrs",
    "tcl_list_literal",
)
load("//vivado/private:transitions.bzl", "hook_transition")

def _vivado_project_impl(ctx):
    if ctx.attr.module:
        hdl = hdl_sources_data(ctx.attr.module)
        hdl_all_files = hdl.all_files
        hdl_sources_literal = hdl.hdl_sources
        src_dirs_literal = hdl.src_dirs
        xdc_files_literal = hdl.xdc_files
        tcl_files_literal = hdl.tcl_files
    else:
        # No top-level HDL library. `vivado_export_simulation` in
        # IP-only-export mode is the main use case — the design lives
        # entirely inside `ip_blocks` / `block_designs`, and there's no
        # user HDL to load. Empty Tcl-list literals keep the template's
        # foreach loops well-formed.
        hdl_all_files = []
        hdl_sources_literal = "{}"
        src_dirs_literal = "{}"
        xdc_files_literal = "{}"
        tcl_files_literal = "{}"
    ip = ip_blocks_data(ctx.attr.ip_blocks)
    bd = block_designs_data(ctx.attr.block_designs)

    # `data` is the escape hatch for constraint files whose relative
    # ordering matters. Files are loaded in exact `data =` list order
    # AFTER the HDL-walk-swept `$XDC_FILES` (per-library foundations),
    # so project-scope constraints layer on top — a `set_clock_groups`
    # that references clocks defined in an earlier `create_clock` file
    # only works if both live here and are ordered correctly. Files
    # whose order doesn't matter should live on `verilog_library.data`
    # or `vhdl_library.data` instead and ride the HDL dep graph.
    project_data_files = ctx.files.data
    project_data_paths = tcl_list_literal([f.path for f in project_data_files])

    pre_early = hook_invocation(ctx, ctx.attr.pre_hooks_early)
    pre = hook_invocation(ctx, ctx.attr.pre_hooks)

    # Collect `project_hooks` contributions from each BD / IP target
    # listed in `block_designs` + `ip_blocks`. Fires before this project's
    # own `pre_hooks_early` so the project author gets last-write-wins.
    contributed = merge_project_hook_contributions(
        ctx = ctx,
        block_designs = ctx.attr.block_designs,
        ip_blocks = ctx.attr.ip_blocks,
    )

    # Merge BD-transitive IP repos into IP_REPOS so `create_bd_cell -vlnv`
    # calls inside a passed-through BD resolve at BD-reload time.
    merged_ip_repo_paths = ip.ip_repo_paths + bd.ip_repo_paths

    project_tcl = ctx.actions.declare_file("{}.project.tcl".format(ctx.label.name))

    ctx.actions.expand_template(
        template = ctx.file.project_tcl_template,
        output = project_tcl,
        substitutions = {
            "{{BLOCK_DESIGNS}}": bd.block_designs,
            "{{CONTRIBUTED_PROJECT_HOOKS}}": contributed.files_literal,
            "{{HDL_SOURCES}}": hdl_sources_literal,
            "{{IP_CONFIGURED_INSTANCES}}": ip.ip_configured_instances,
            "{{IP_INSTANCES}}": ip.ip_instances,
            "{{IP_REPOS}}": tcl_list_literal(merged_ip_repo_paths),
            "{{MODULE_TOP}}": ctx.attr.module_top,
            "{{PART_NUMBER}}": ctx.attr.part_number,
            "{{PRE_HOOKS_EARLY}}": pre_early.files_literal,
            "{{PRE_HOOKS}}": pre.files_literal,
            "{{PROJECT_DATA_FILES}}": project_data_paths,
            "{{SRC_DIRS}}": src_dirs_literal,
            "{{TCL_FILES}}": tcl_files_literal,
            "{{XDC_FILES}}": xdc_files_literal,
        },
    )

    # Everything the emitted script's `source` / `read_*` / `add_files` /
    # `file copy` calls will try to open. `hook_invocation.tools` is a
    # mixed File / FilesToRunProvider list carried separately in
    # `hook_tools` — the consumer feeds it to `run_shell(tools=...)` so
    # `tcl_binary` runfiles trees materialize; a depset can't hold
    # FilesToRunProvider so we can't merge the two.
    input_files = depset(
        direct = hdl_all_files + ip.input_files + bd.input_files + project_data_files,
    )
    hook_tools = contributed.tools + pre_early.tools + pre.tools

    # Typed sub-provider access. Downstream consumers walking `VivadoProjectInfo`
    # can filter/introspect BDs / IPs / XDCs without re-reading rule attrs.
    bd_provider_list = [t[VivadoBlockDesignInfo] for t in ctx.attr.block_designs]
    ip_provider_list = [t[VivadoIPBlockInfo] for t in ctx.attr.ip_blocks]

    # `project_data_files` (= `ctx.files.data`) IS the load order the
    # emitted `$PROJECT_DATA_FILES` loop walks: plain files sit at their
    # listed position and an `xdc_library` target's DefaultInfo.files —
    # already a dep-first topological depset — flattens in place where the
    # target appears. Splitting the two into `direct` + `transitive` here
    # would group all `xdc_library` content ahead of all plain files, so
    # the provider would advertise an order the action never uses.
    xdc_depset = depset(direct = project_data_files)

    return [
        DefaultInfo(files = depset([project_tcl])),
        VivadoProjectInfo(
            project_tcl = project_tcl,
            input_files = input_files,
            hook_tools = hook_tools,
            module_top = ctx.attr.module_top,
            part_number = ctx.attr.part_number,
            block_designs = bd_provider_list,
            ip_blocks = ip_provider_list,
            xdc = xdc_depset,
        ),
    ]

vivado_project = rule(
    implementation = _vivado_project_impl,
    doc = """Emit a TCL project-creation script. Does NOT invoke Vivado.

A spec-carrying rule: its sole build-time action is a template expansion
producing `<name>.project.tcl`, which — sourced inside a Vivado process
— runs `create_project`, source ingest, constraints, and hooks. It stops
short of `generate_target`, because the right intent (`{synthesis
implementation}` vs `simulation`) depends on the consumer; each consumer
issues its own after sourcing.

Two ways to consume it:

- `vivado_synthesis` (and the other phase rules) take
  `project = <label>` and source the emitted script inside their Vivado
  action before doing their own work.
- A GUI launcher can `vivado -source <name>.project.tcl` directly. The
  script's `PROJECT_MODE` / `PROJECT_DIR` variables default to `project`
  mode in `.`; override them with `VIVADO_PROJECT_MODE` /
  `VIVADO_PROJECT_DIR`, or by pre-setting the Tcl variables before
  sourcing.

Provides `VivadoProjectInfo`.
""",
    attrs = {
        "block_designs": attr.label_list(
            doc = ("Block designs (`vivado_block_design` targets) to fold " +
                   "into the project. Copied under " +
                   "`$PROJECT_DIR/imported_bds/<name>/` and `add_files`d. " +
                   "The consumer (`vivado_synthesis` / `vivado_xsim_test`) " +
                   "picks the appropriate `generate_target` intent " +
                   "(`{synthesis implementation}` vs `simulation`)."),
            providers = [VivadoBlockDesignInfo],
            default = [],
        ),
        "data": attr.label_list(
            doc = ("Constraint / setup files (`.xdc`, `.sdc`, `.tcl`) " +
                   "loaded in EXACT list order — the escape hatch for " +
                   "files whose relative ordering matters (e.g. a " +
                   "`set_clock_groups.xdc` that references clocks defined " +
                   "in a `create_clock.xdc` sourced earlier). Loaded AFTER " +
                   "the HDL-walk-swept `.xdc` files from " +
                   "`verilog_library.data` / `vhdl_library.data`, so " +
                   "project-scope constraints layer on top of per-library " +
                   "foundations. `.xdc`/`.sdc` → `read_xdc`, `.tcl` → " +
                   "`source`. Files whose order doesn't matter should live " +
                   "on the HDL library's `.data` instead and ride the HDL " +
                   "dep graph.\n\n" +
                   "Put a `# do not sort` comment above an order-sensitive " +
                   "list. buildifier sorts `data` lists by default, so " +
                   "without it a routine format pass silently rewrites the " +
                   "constraint load order — nothing fails until Vivado " +
                   "applies the wrong constraints."),
            allow_files = [".xdc", ".sdc", ".tcl"],
            default = [],
        ),
        "ip_blocks": attr.label_list(
            doc = "IP blocks to include in this design.",
            providers = [VivadoIPBlockInfo],
            default = [],
        ),
        "module": attr.label(
            doc = ("Top-level HDL library. Optional — omit for IP-only " +
                   "projects (e.g. `vivado_export_simulation` in " +
                   "sim-from-packaged-IPs mode). When set, its transitive " +
                   "sources are `read_verilog` / `read_vhdl`d and its `.xdc` " +
                   "/ `.tcl` files are added; when unset, only `ip_blocks` / " +
                   "`block_designs` contribute sources."),
            providers = [[VerilogInfo], [VhdlInfo]],
        ),
        "module_top": attr.string(
            doc = "The name of the top level verilog module.",
            mandatory = True,
        ),
        "part_number": attr.string(
            doc = "The targeted xilinx part.",
            mandatory = True,
        ),
        "pre_hooks": attr.label_list(
            doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced AFTER all `add_files` but BEFORE the emitted " +
                   "script returns control to its caller. Home for hooks " +
                   "that need sources loaded but must run before any " +
                   "`generate_target` — e.g. `fixup_constraints.tcl` " +
                   "calling `get_files -of [get_ips]`. For post-elaboration " +
                   "hooks, use the consumer's `pre_hooks` " +
                   "(`vivado_synthesis.pre_hooks`, `vivado_xsim_test.pre_hooks`). " +
                   "For hooks that set project properties (`board_part`) " +
                   "or define TCL procs used by BD sources, use " +
                   "`pre_hooks_early`. Sourced in list order."),
            allow_files = DEFAULT_HOOK_EXTS,
            cfg = hook_transition,
            default = [],
        ),
        "pre_hooks_early": attr.label_list(
            doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced AFTER `create_project` but BEFORE any " +
                   "`add_files`. Home for hooks that set project-scope " +
                   "properties (`board_part`, `set_msg_config`) or define " +
                   "TCL procs consumed by BD `.tcl` scripts loaded during " +
                   "add_files (e.g. `amba::add_associated_busif`, `noc::*`). " +
                   "Sourced in list order."),
            allow_files = DEFAULT_HOOK_EXTS,
            cfg = hook_transition,
            default = [],
        ),
        "project_tcl_template": attr.label(
            doc = "Template driving the emitted project TCL.",
            default = Label("//vivado/private:project.tcl.template"),
            allow_single_file = [".template"],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | tcl_hook_flag_attrs(),
    provides = [DefaultInfo, VivadoProjectInfo],
    # No Vivado action here. Requiring the toolchain anyway keeps a
    # `vivado_project` analyzable exactly where its consumers are, so a
    # missing toolchain surfaces at the project rather than one rule later.
    toolchains = [TOOLCHAIN_TYPE],
)
