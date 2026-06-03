"""# Simulation rules"""

load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    "//vivado:providers.bzl",
    "VivadoCompiledSimlibInfo",
    "VivadoExportSimulationInfo",
    "VivadoProjectInfo",
)
load(
    "//vivado/private:common.bzl",
    "EXECROOT_MARKER",
    "TOOLCHAIN_TYPE",
    "exec_hooks_data",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "run_tcl_template",
)

_SIMULATOR_CHOICES = [
    "activehdl",
    "ies",
    "modelsim",
    "questa",
    "riviera",
    "vcs",
    "vcs_mx",
    "xcelium",
    "xsim",
]

_DEFAULT_XSIM_ERROR_PATTERNS = [
    "^Error: ",
    "^ERROR:",
    "FATAL_ERROR",
    "\\$fatal",
]

_DEFAULT_XSIM_COMPLETION_PATTERN = "\\$finish"

def _sim_top_or_fail(ctx):
    """Simulation-fileset top must be set explicitly (Vivado refuses `export_simulation` otherwise)."""
    if not ctx.attr.module_top:
        fail(("{}: `module_top` must be set explicitly. Point it at the " +
              "simulation-fileset top module (typically the testbench, or " +
              "`<bd>_wrapper` for a BD-only sim).").format(ctx.label))
    return ctx.attr.module_top

def _run_export_simulation(
        *,
        ctx,
        toolchain,
        simulator,
        export_dir,
        project_dir,
        pre_tcl,
        post_tcl,
        pre_exec,
        post_exec,
        mnemonic):
    """Shared setup between vivado_export_simulation + vivado_xsim_test.

    Both rules source the same emitted `.project.tcl` and run
    `export_simulation` on the resulting project. This helper builds the
    action; each caller owns the outputs it wants (export_dir alone for
    vivado_export_simulation; export_dir + wrapper for vivado_xsim_test).
    """
    project_info = ctx.attr.project[VivadoProjectInfo]
    sim_top = _sim_top_or_fail(ctx)

    substitutions = {
        "{{EXPORT_DIR}}": export_dir.path,
        "{{POST_HOOKS}}": post_tcl.files_literal,
        "{{PRE_HOOKS}}": pre_tcl.files_literal,
        "{{PROJECT_DIR}}": project_dir.path,
        "{{PROJECT_TCL}}": project_info.project_tcl.path,
        "{{SIMULATOR}}": simulator,
        "{{SIM_TOP}}": sim_top,
    }

    input_files = (
        [project_info.project_tcl] + project_info.input_files.to_list()
    )

    merged_hook_env = dict(pre_exec.env)
    for k, v in post_exec.env.items():
        merged_hook_env[k] = v

    return run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.export_simulation_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = [export_dir, project_dir],
        mnemonic = mnemonic,
        pre_processing_command = pre_exec.command,
        post_processing_command = post_exec.command,
        tools = (
            project_info.hook_tools +
            pre_exec.tools + post_exec.tools +
            pre_tcl.tools + post_tcl.tools
        ),
        hook_env = merged_hook_env,
    )

def _vivado_xsim_test_impl(ctx):
    if ctx.attr.with_waveform:
        fail(("{}: `with_waveform = True` is not wired end-to-end. To " +
              "capture waveforms, add a `pre_hooks` Tcl script that " +
              "sets `xsim.simulate.log_all_signals` (and, if needed, " +
              "`xsim.simulate.wdb`) on the sim fileset before " +
              "`export_simulation` runs; any `.wdb` the run produces is " +
              "copied to `$TEST_UNDECLARED_OUTPUTS_DIR` automatically. " +
              "Silently accepting the flag while producing no waveform " +
              "was the prior behavior and is now rejected.").format(ctx.label))

    toolchain = get_vivado_toolchain(ctx)
    export_dir = ctx.actions.declare_directory("{}_export".format(ctx.label.name))
    project_dir = ctx.actions.declare_directory("{}_prj".format(ctx.label.name))

    pre_tcl = hook_invocation(ctx, ctx.attr.pre_hooks)
    post_tcl = hook_invocation(ctx, ctx.attr.post_hooks)
    pre_exec = exec_hooks_data(
        ctx.attr.pre_hook_tools,
        project_dir_path = project_dir.path,
        export_dir_path = export_dir.path,
    )
    post_exec = exec_hooks_data(
        ctx.attr.post_hook_tools,
        project_dir_path = project_dir.path,
        export_dir_path = export_dir.path,
    )

    _run_export_simulation(
        ctx = ctx,
        toolchain = toolchain,
        simulator = "xsim",
        export_dir = export_dir,
        project_dir = project_dir,
        pre_tcl = pre_tcl,
        post_tcl = post_tcl,
        pre_exec = pre_exec,
        post_exec = post_exec,
        mnemonic = "VivadoXSimExport",
    )

    # Patterns go through `shell.quote`, which escapes embedded single
    # quotes, so any ERE is accepted as-is.
    error_pattern_ere = "|".join(ctx.attr.error_patterns)
    completion_pattern_ere = ctx.attr.completion_pattern

    xilinx_env_short_path = toolchain.xilinx_env.short_path if toolchain.xilinx_env else ""

    # The toolchain's `vivado` shim rides along so the wrapper can locate
    # the install (and thus `xvlog` / `xelab` / `xsim`) when neither
    # `xilinx_env` nor `env` put them on PATH. Only the executable itself
    # is staged — a `FilesToRunProvider` carries no runfiles object — which
    # covers the shell-shim shape every documented toolchain uses.
    vivado_exe = toolchain.vivado.executable

    env_lines = []
    for k, v in toolchain.env.items():
        env_lines.append("export {}={}".format(k, shell.quote(v)))
    env_exports = "\n".join(env_lines)

    ctx.actions.expand_template(
        template = ctx.file.xsim_test_wrapper_template,
        output = ctx.outputs.executable,
        substitutions = {
            "{{COMPLETION_PATTERN}}": shell.quote(completion_pattern_ere),
            "{{ENV_EXPORTS}}": env_exports,
            "{{ERROR_PATTERN}}": shell.quote(error_pattern_ere),
            "{{EXECROOT_MARKER}}": shell.quote(EXECROOT_MARKER),
            "{{EXPORT_DIR_SHORT_PATH}}": shell.quote(export_dir.short_path),
            "{{TEST_NAME}}": shell.quote(ctx.label.name),
            "{{VIVADO_SHORT_PATH}}": shell.quote(vivado_exe.short_path),
            "{{XILINX_ENV_SHORT_PATH}}": shell.quote(xilinx_env_short_path),
        },
        is_executable = True,
    )

    project_info = ctx.attr.project[VivadoProjectInfo]

    # Vivado's `export_simulation` copies only HDL sources into the export tree,
    # dropping `.mem` init files and other `data =` payloads. Stage every
    # transitive file so runtime references like `$readmemh "tests/foo/init.mem"`
    # resolve.
    runfiles_files = [export_dir, vivado_exe] + project_info.input_files.to_list()
    if toolchain.xilinx_env:
        runfiles_files.append(toolchain.xilinx_env)

    return [
        DefaultInfo(
            executable = ctx.outputs.executable,
            runfiles = ctx.runfiles(files = runfiles_files),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["project"],
        ),
    ]

def _sim_module_top_attr():
    return attr.string(
        doc = ("Simulation-fileset top module. Typically the testbench " +
               "name, or `<bd>_wrapper` for a BD-only sim."),
        mandatory = True,
    )

def _export_simulation_template_attr():
    return attr.label(
        doc = "The tcl template that drives `export_simulation`.",
        default = Label("//vivado/private:export_simulation.tcl.template"),
        allow_single_file = [".template"],
    )

def _project_attr():
    return attr.label(
        doc = ("`vivado_project` target carrying the emitted project " +
               "TCL script + its transitive input closure. All " +
               "project-shape attrs (module, part_number, block_designs, " +
               "ip_blocks, pre_hooks_early, etc.) live on that target."),
        providers = [VivadoProjectInfo],
        mandatory = True,
    )

vivado_xsim_test = rule(
    doc = """Run a Vivado xsim simulation as a Bazel test.

A build action sources the `vivado_project`-emitted project TCL,
generates simulation targets on any BDs, and calls `export_simulation`
to produce a self-contained xsim script bundle; the test binary runs
`simulate.sh` at test time. Log-scan patterns catch `$error` output,
which xsim prints but doesn't exit nonzero for. The wrapper writes a
JUnit XML at `$XML_OUTPUT_FILE` and copies the sim log, per-tool logs,
and any `.wdb` waveform into `$TEST_UNDECLARED_OUTPUTS_DIR`.

At test time the wrapper re-points the bundle's sanitized `<execroot>/`
paths at its runfiles, then needs `xvlog` / `xelab` / `xsim` on `PATH`.
Bazel hands tests a minimal `PATH`, so supply them through the
toolchain's `xilinx_env` script (sourced by the wrapper) or an
`env = {"PATH": ...}` entry; failing both, the wrapper boots the
toolchain's `vivado` shim once to discover the install's `bin` dir.
""",
    implementation = _vivado_xsim_test_impl,
    test = True,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "completion_pattern": attr.string(
            doc = ("ERE pattern the simulation log must match for the test " +
                   "to pass. Set to `\"\"` to disable. Only consulted when " +
                   "the driver script exited 0."),
            default = _DEFAULT_XSIM_COMPLETION_PATTERN,
        ),
        "error_patterns": attr.string_list(
            doc = ("ERE patterns that mark the simulation log as failed. " +
                   "Joined with `|` and passed to `grep -E`. Pass `[]` to " +
                   "disable log scanning."),
            default = _DEFAULT_XSIM_ERROR_PATTERNS,
        ),
        "export_simulation_template": _export_simulation_template_attr(),
        "module_top": _sim_module_top_attr(),
        "post_hook_tools": attr.label_list(
            doc = ("Executable targets invoked in the same Bazel action AFTER " +
                   "Vivado exits. Each receives `--project-dir <path> " +
                   "--export-dir <path>` and the same paths via " +
                   "`VIVADO_PROJECT_DIR` / `VIVADO_EXPORT_DIR` env vars. Order " +
                   "is preserved; first non-zero exit fails the action."),
            cfg = "exec",
            default = [],
        ),
        "pre_hook_tools": attr.label_list(
            doc = "Executable targets invoked BEFORE Vivado starts; see `post_hook_tools`.",
            cfg = "exec",
            default = [],
        ),
        "project": _project_attr(),
        "with_waveform": attr.bool(
            doc = ("Only `False` is accepted; `True` fails at analysis. To " +
                   "capture waveforms, add a `pre_hooks` Tcl script that " +
                   "sets `xsim.simulate.log_all_signals` on the sim fileset."),
            default = False,
        ),
        "xsim_test_wrapper_template": attr.label(
            doc = "Bash template driving the exported `simulate.sh` at test time.",
            default = Label("//vivado/private:xsim_test_wrapper.sh.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl` files OR `tcl_binary` targets sourced after " +
                    "`export_simulation` completes, with the project still " +
                    "open. Sourced in list order."),
        pre_doc = ("`.tcl` files OR `tcl_binary` targets sourced after " +
                   "the project script + sim elaboration, before " +
                   "`export_simulation` runs. Sourced in list order."),
        extensions = [".tcl"],
    ),
)

def _vivado_export_simulation_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)
    export_dir = ctx.actions.declare_directory(ctx.label.name)
    project_dir = ctx.actions.declare_directory("{}_prj".format(ctx.label.name))

    pre_tcl = hook_invocation(ctx, ctx.attr.pre_hooks)
    post_tcl = hook_invocation(ctx, ctx.attr.post_hooks)
    pre_exec = exec_hooks_data(
        ctx.attr.pre_hook_tools,
        project_dir_path = project_dir.path,
        export_dir_path = export_dir.path,
    )
    post_exec = exec_hooks_data(
        ctx.attr.post_hook_tools,
        project_dir_path = project_dir.path,
        export_dir_path = export_dir.path,
    )

    result = _run_export_simulation(
        ctx = ctx,
        toolchain = toolchain,
        simulator = ctx.attr.simulator,
        export_dir = export_dir,
        project_dir = project_dir,
        pre_tcl = pre_tcl,
        post_tcl = post_tcl,
        pre_exec = pre_exec,
        post_exec = post_exec,
        mnemonic = "VivadoExportSimulation",
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoExportSimulationInfo(
            export_dir = export_dir,
            simulator = ctx.attr.simulator,
            project_info = ctx.attr.project[VivadoProjectInfo],
            tcl = result.vivado_tcl,
        ),
    ]

vivado_export_simulation = rule(
    doc = """Run Vivado's `export_simulation` over a `vivado_project` and
stage the resulting directory as a TreeArtifact. The downstream
simulator is not run; consumers compose against `VivadoExportSimulationInfo`.

The exported `compile.sh` / `elaborate.sh` / `simulate.sh` scripts are
path-sanitized like every other output: absolute paths become
`<execroot>/` so the tree stays cacheable across hosts and RBE workers.
The bundle is therefore not runnable straight out of `bazel-bin` — a
consumer re-points the marker at its own root first (`sed -i
"s|<execroot>/|$PWD/|g"`). See `vivado_toolchain(sanitizer = ...)`.
""",
    implementation = _vivado_export_simulation_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "export_simulation_template": _export_simulation_template_attr(),
        "module_top": _sim_module_top_attr(),
        "post_hook_tools": attr.label_list(
            doc = ("Executable targets invoked in the same Bazel action AFTER " +
                   "Vivado exits. Each receives `--project-dir <path> " +
                   "--export-dir <path>` and the same paths via " +
                   "`VIVADO_PROJECT_DIR` / `VIVADO_EXPORT_DIR` env vars. Order " +
                   "is preserved; first non-zero exit fails the action."),
            cfg = "exec",
            default = [],
        ),
        "pre_hook_tools": attr.label_list(
            doc = "Executable targets invoked BEFORE Vivado starts; see `post_hook_tools`.",
            cfg = "exec",
            default = [],
        ),
        "project": _project_attr(),
        "simulator": attr.string(
            doc = "Target simulator for the export.",
            mandatory = True,
            values = _SIMULATOR_CHOICES,
        ),
    } | hook_attrs(
        post_doc = ("`.tcl` files OR `tcl_binary` targets sourced inside " +
                    "Vivado at the end of the export body, with the project " +
                    "still open. Sourced in list order."),
        pre_doc = ("`.tcl` files OR `tcl_binary` targets sourced after " +
                   "the project script + sim elaboration, before " +
                   "`export_simulation` runs. Sourced in list order."),
        extensions = [".tcl"],
    ),
    provides = [
        DefaultInfo,
        VivadoExportSimulationInfo,
    ],
)

# Riviera-PRO and Active-HDL are independent FlexLM features on the same Aldec
# server, so they get separate pools. Simulators absent from this map get no
# license claim by default; callers override via `license_resource_name`.
_DEFAULT_LICENSE_RESOURCE_BY_SIMULATOR = {
    "activehdl": ("activehdl_license", 1),
    "riviera": ("riviera_license", 1),
}

# Per-simulator install-root env var and bin subdir. `compile_simlib` shells
# out to vsimsa AND its peer tools (vlib/vlog/vcom/etc.), so a single Bazel-
# tracked binary isn't enough. Mentor's `MODEL_TECH` is already the bin dir.
_INSTALL_ENV_VAR = {
    "activehdl": ("ALDEC_PATH", "/bin"),
    "ies": ("CDS_INST_DIR", "/tools/bin"),
    "modelsim": ("MODEL_TECH", ""),
    "questa": ("QUESTA_HOME", "/bin"),
    "riviera": ("RIVIERA_HOME", "/bin"),
    "vcs": ("VCS_HOME", "/bin"),
    "vcs_mx": ("VCS_HOME", "/bin"),
    "xcelium": ("CDS_INST_DIR", "/tools/bin"),
}

def _vivado_compile_simlib_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)
    simlib_dir = ctx.actions.declare_directory(ctx.label.name)

    install_env_var, install_bin_subdir = _INSTALL_ENV_VAR[ctx.attr.simulator]

    substitutions = {
        "{{FAMILY}}": ctx.attr.family,
        "{{INSTALL_BIN_SUBDIR}}": install_bin_subdir,
        "{{INSTALL_ENV_VAR}}": install_env_var,
        "{{LANGUAGE}}": ctx.attr.language,
        "{{LIBRARY}}": ctx.attr.library,
        "{{NO_IP_COMPILE}}": "1" if ctx.attr.no_ip_compile else "0",
        "{{NO_SYSTEMC_COMPILE}}": "1" if ctx.attr.no_systemc_compile else "0",
        "{{SIMLIB_DIR}}": simlib_dir.path,
        "{{SIMULATOR}}": ctx.attr.simulator,
    }

    if ctx.attr.license_resource_name:
        resource_name = ctx.attr.license_resource_name
        count = ctx.attr.license_resource_count if ctx.attr.license_resource_count > 0 else 1
    elif ctx.attr.simulator in _DEFAULT_LICENSE_RESOURCE_BY_SIMULATOR:
        resource_name, count = _DEFAULT_LICENSE_RESOURCE_BY_SIMULATOR[ctx.attr.simulator]
    else:
        resource_name, count = "", 0

    extra_execution_requirements = {}
    if resource_name:
        extra_execution_requirements["resources:{}".format(resource_name)] = str(count)

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.compile_simlib_template,
        substitutions = substitutions,
        input_files = [],
        output_files = [simlib_dir],
        mnemonic = "VivadoCompileSimlib",
        extra_execution_requirements = extra_execution_requirements,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoCompiledSimlibInfo(
            simlib_dir = simlib_dir,
            simulator = ctx.attr.simulator,
        ),
    ]

vivado_compile_simlib = rule(
    doc = """Pre-compile the Xilinx baseline simulation libraries (`unisim`,
`unimacro`, `secureip`, `unifast`, ...) for a third-party simulator. Output is
a TreeArtifact at the layout `compile_simlib -directory <dir>` produces.

`compile_simlib` is hours of work for `-family all`; pass a specific silicon
family to bound the scope. The simulator install is located via an env-var
lookup on the exec platform (`$RIVIERA_HOME` for riviera, etc.) because
`compile_simlib` shells out to vsimsa AND its peer tools.
""",
    implementation = _vivado_compile_simlib_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "compile_simlib_template": attr.label(
            doc = "The tcl template that drives `compile_simlib`.",
            default = Label("//vivado/private:compile_simlib.tcl.template"),
            allow_single_file = [".template"],
        ),
        "family": attr.string(
            doc = ("Xilinx silicon family, passed to `compile_simlib -family <X>`. " +
                   "Common values: `all` (hours), `versal`, `kintexuplus`, `zynquplus`."),
            mandatory = True,
        ),
        "language": attr.string(
            doc = "HDL language, passed to `compile_simlib -language <X>`.",
            default = "all",
            values = ["all", "vhdl", "verilog"],
        ),
        "library": attr.string(
            doc = ("Simulation library set, passed to `compile_simlib -library <X>`. " +
                   "For families whose `all` set omits a needed library, compile " +
                   "that library in a second target with `no_ip_compile = True` " +
                   "and chain via `vmap -link` at consume time."),
            default = "all",
        ),
        "license_resource_count": attr.int(
            doc = ("Number of `license_resource_name` units to claim. Values <= 0 " +
                   "fall back to 1 when a resource name is set."),
            default = 0,
        ),
        "license_resource_name": attr.string(
            doc = ("FlexLM feature name to claim from Bazel's local resource pool. " +
                   "Callers wire the pool via `--local_extra_resources=<name>=N`. " +
                   "Overrides the built-in default map (activehdl, riviera). Empty " +
                   "falls back to that map."),
            default = "",
        ),
        "no_ip_compile": attr.bool(
            doc = ("Pass `-no_ip_compile`. Required on chained follow-up targets: " +
                   "Vivado rewrites `library.cfg` on each `compile_simlib`, so a " +
                   "later call's IP compile pass errors with `Library \"<baseline>\" " +
                   "not found` because the fresh `library.cfg` lacks the baseline " +
                   "mappings the IPs reference."),
            default = False,
        ),
        "no_systemc_compile": attr.bool(
            doc = ("Pass `-no_systemc_compile` (default true). The SystemC libs " +
                   "require a working SystemC install reachable by the simulator's " +
                   "C++ toolchain, which often isn't present in CI images."),
            default = True,
        ),
        "simulator": attr.string(
            doc = "Target simulator. `xsim` is built into Vivado and doesn't need precompile.",
            mandatory = True,
            values = sorted(_INSTALL_ENV_VAR.keys()),
        ),
    },
    provides = [
        DefaultInfo,
        VivadoCompiledSimlibInfo,
    ],
)
