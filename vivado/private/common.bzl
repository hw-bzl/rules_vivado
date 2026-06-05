"""Shared helpers used by every vivado rule."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoIPBlockInfo")
load("//vivado:toolchain.bzl", _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE")
load(":resource_set.bzl", "get_resource_set")

TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE

def get_vivado_toolchain(ctx):
    """Resolve the Vivado toolchain settings for an action.

    Args:
        ctx: The rule context.

    Returns:
        VivadoToolchainInfo struct (xilinx_env: File, requires_network: bool,
        env: dict[str, str]).
    """
    return ctx.toolchains[TOOLCHAIN_TYPE].vivado_info

def run_tcl_template(*, ctx, template, substitutions, input_files, output_files, mnemonic, jobs = 1, post_processing_command = ""):
    """Runs a tcl template in vivado.

    Args:
        ctx: Context from a rule.
        template: The template file to use.
        substitutions: The substitutions to apply to the template.
        input_files: A list of input files that vivado needs to run.
        output_files: A list of expected outputs from the tcl script running on vivado.
        mnemonic: A short CamelCase identifier shown in Bazel output for this action.
        jobs: How many CPUs Vivado will use for this action. Used as the
            `resource_set` hint to Bazel's scheduler. Clamped at
            MAX_VIVADO_THREADS. Pass 1 (the default) for single-threaded actions.
        post_processing_command: A bash command to run after vivado.

    Returns:
        DefaultInfo - The files that were created.
    """
    env = get_vivado_toolchain(ctx)
    vivado_tcl = ctx.actions.declare_file("{}_run_vivado.tcl".format(ctx.label.name))
    vivado_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    vivado_journal = ctx.actions.declare_file("{}.jou".format(ctx.label.name))

    ctx.actions.expand_template(
        template = template,
        output = vivado_tcl,
        substitutions = substitutions,
    )

    # `xilinx_env` is the toolchain's optional shell-side escape hatch.
    # Only fires when set — static env flows through `ctx.actions.run_shell`
    # via `env.env`.
    vivado_command = ""
    if env.xilinx_env:
        vivado_command += "source " + env.xilinx_env.path + " && "
    vivado_command += "vivado -mode batch -source " + vivado_tcl.path
    vivado_command += " -log " + vivado_log.path
    vivado_command += " -journal " + vivado_journal.path + "; "
    vivado_command += post_processing_command

    outputs = output_files + [vivado_log, vivado_journal]
    action_inputs = input_files + [vivado_tcl]
    if env.xilinx_env:
        action_inputs.append(env.xilinx_env)

    # Network access is opt-in via the toolchain's `requires_network` attribute
    # (true by default for floating/network license servers; false for
    # license-free editions or node-locked .lic files). Sandboxing and remote
    # caching are deliberately left enabled: the sandbox provides a writable
    # cwd + /tmp (HOME is pinned to /tmp by the toolchain script), and Bazel's
    # action-keyed remote cache is exactly the win you want for hours-long
    # synthesis runs — every cache hit is the same upload byte-for-byte.
    execution_requirements = {}
    if env.requires_network:
        execution_requirements["requires-network"] = ""

    ctx.actions.run_shell(
        outputs = outputs,
        inputs = action_inputs,
        progress_message = "Running on vivado: {}".format(ctx.label.name),
        command = vivado_command,
        mnemonic = mnemonic,
        toolchain = TOOLCHAIN_TYPE,
        resource_set = get_resource_set(jobs),
        execution_requirements = execution_requirements,
        env = env.env,
    )

    return [
        DefaultInfo(files = depset(outputs)),
        vivado_log,
        vivado_journal,
    ]

_DEFAULT_VHDL_LIBRARY = "xil_defaultlib"

def _file_to_tcl_buckets(file, vhdl_library):
    """Return (hdl, constraints, tcl) Tcl strings for one input file.

    Empty strings for the buckets the file doesn't contribute to. IP-XACT
    metadata (.xml/.json) is skipped — its own rules handle it.
    """
    if file.extension == "v":
        return "read_verilog -library xil_defaultlib " + file.path + "\n", "", ""
    if file.extension == "sv":
        return "read_verilog -library xil_defaultlib -sv " + file.path + "\n", "", ""
    if file.extension in ["vhd", "vhdl"]:
        return "read_vhdl -library {} {}\n".format(vhdl_library, file.path), "", ""
    if file.extension == "tcl":
        return "", "", "source " + file.path + "\n"
    if file.extension == "xdc":
        return "", "read_xdc " + file.path + "\n", ""
    if file.extension in ["xml", "json"]:
        return "", "", ""

    # Generic catch-all (coef, mem, txt, ...).
    return "import_files " + file.path + "\n", "", ""

def generate_file_load_tcl(module):
    """Generate the strings needed for tcl.

    Walk a module's transitive sources and emit `read_verilog`/`read_vhdl`/
    `read_xdc`/`source`/`import_files` Tcl lines. The module may carry either
    `VerilogInfo` (rules_verilog) or `VhdlInfo` (rules_vhdl); both providers
    expose `deps` as a depset of like-typed transitive providers plus direct-
    only `srcs`/`data` depsets (VerilogInfo also has `hdrs`).

    For VHDL sources, `read_vhdl -library <name>` honors the VhdlInfo `library`
    field — falling back to "xil_defaultlib" if unset. .vhd files reached via a
    `VerilogInfo.data` slot fall back to the same default since rules_verilog
    has no per-library VHDL naming concept.

    Args:
        module: The top level HDL library target.

    Returns:
        all_files: Every file the module depends on.
        hdl_source_content: Tcl that loads HDL sources.
        constraints_content: Tcl that loads .xdc constraints.
        tcl_content: Tcl that sources additional .tcl files.
    """
    all_files = []
    hdl_source_content = ""
    constraints_content = ""
    tcl_content = ""

    if VerilogInfo in module:
        info = module[VerilogInfo]
        for v in info.deps.to_list() + [info]:
            files = v.srcs.to_list() + v.hdrs.to_list() + v.data.to_list()
            all_files += files
            for f in files:
                hdl, con, tcl = _file_to_tcl_buckets(f, _DEFAULT_VHDL_LIBRARY)
                hdl_source_content += hdl
                constraints_content += con
                tcl_content += tcl

    if VhdlInfo in module:
        info = module[VhdlInfo]
        for v in info.deps.to_list() + [info]:
            vhdl_library = v.library if v.library else _DEFAULT_VHDL_LIBRARY
            files = v.srcs.to_list() + v.data.to_list()
            all_files += files
            for f in files:
                hdl, con, tcl = _file_to_tcl_buckets(f, vhdl_library)
                hdl_source_content += hdl
                constraints_content += con
                tcl_content += tcl

    return [
        all_files,
        hdl_source_content,
        constraints_content,
        tcl_content,
    ]

def generate_ip_block_tcl(ip_blocks):
    """Generate the tcl for including an IP repo.

    Args:
        ip_blocks: A list of ip blocks to include that provide VivadoIPBlockInfo.

    Returns:
        The tcl to include the paths to the ip blocks.
    """
    ip_tcl = "set_property ip_repo_paths [list "
    for ip_block in ip_blocks:
        for repo in ip_block[VivadoIPBlockInfo].repo:
            ip_tcl += "{} ".format(repo.path)
    ip_tcl += "] [current_project]\n"
    for ip_block in ip_blocks:
        if ip_block[VivadoIPBlockInfo].is_interface:
            continue
        ip_tcl += "create_ip -name {} -vendor {} -library {} -version {} -module_name {}\n".format(
            ip_block[VivadoIPBlockInfo].module_top,
            ip_block[VivadoIPBlockInfo].vendor,
            ip_block[VivadoIPBlockInfo].library,
            ip_block[VivadoIPBlockInfo].version,
            ip_block[VivadoIPBlockInfo].module_top + "_ip",
        )
    ip_tcl += "update_ip_catalog\n"
    return ip_tcl

def create_and_synth(
        *,
        ctx,
        with_synth,
        synth_checkpoint = None,
        timing_summary_report = None,
        util_report = None,
        synth_strategy = None):
    """Create a project and optionally synthesize.

    Due to IP issues, it makes sense to do synthesis in project mode.
    This function can also be used to generate a vivado project from the input sources.

    Args:
        ctx: Context from a rule
        with_synth: A flag indicating if synthesis should be run too.
        synth_checkpoint: Optionally define the output synthesis checkpoint. Not used when creating a project only.
        timing_summary_report: Optionally define the timing summary report output. Not used when creating a project only.
        util_report: Optionally define the utilization report output. Not used when creating a project only.
        synth_strategy: Optionally define the synthesis strategy to use. Not used when creating a project only.

    Returns:
        DefaultInfo - Files generated by the project.
    """
    all_files, hdl_source_content, constraints_content, tcl_content = generate_file_load_tcl(ctx.attr.module)

    ip_block_tcl = generate_ip_block_tcl(ctx.attr.ip_blocks)

    project_dir = ctx.actions.declare_directory(ctx.label.name)

    if with_synth:
        synth_path = synth_checkpoint.path
        timing_path = timing_summary_report.path
        util_path = util_report.path
        with_synth_str = "1"
        synth_strategy_str = synth_strategy
        outputs = [project_dir, synth_checkpoint, timing_summary_report, util_report]
    else:
        synth_path = ""
        timing_path = ""
        util_path = ""
        with_synth_str = "0"
        synth_strategy_str = ""
        outputs = [project_dir]

    substitutions = {
        "{{CONSTRAINTS_CONTENT}}": constraints_content,
        "{{HDL_SOURCE_CONTENT}}": hdl_source_content,
        "{{IP_BLOCK_TCL}}": ip_block_tcl,
        "{{JOBS}}": "{}".format(ctx.attr.jobs),
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{PROJECT_DIR}}": project_dir.path,
        "{{SYNTH_CHECKPOINT}}": synth_path,
        "{{SYNTH_STRATEGY}}": synth_strategy_str,
        "{{TCL_CONTENT}}": tcl_content,
        "{{TIMING_SUMMARY_REPORT}}": timing_path,
        "{{UTILIZATION_REPORT}}": util_path,
        "{{WITH_SYNTH}}": with_synth_str,
    }

    ip_block_dirs = []
    for ip_block in ctx.attr.ip_blocks:
        ip_block_dirs += ip_block[VivadoIPBlockInfo].repo

    return run_tcl_template(
        ctx = ctx,
        template = ctx.file.create_project_tcl_template,
        substitutions = substitutions,
        input_files = all_files + ip_block_dirs,
        output_files = outputs,
        mnemonic = "VivadoSynth" if with_synth else "VivadoCreateProject",
        jobs = ctx.attr.jobs,
    )

def generate_encrypt_tcl(*, ctx, all_files, keyfile_path, ip_dir_src):
    """Generate the commands to encrypt all sources.

    Args:
        ctx: The context
        all_files: All files to encrypt
        keyfile_path: Path to the key file used to encrypt.
        ip_dir_src: The location of ip source directory.

    Returns:
        encrypt_content: A string to encrypt all sources.
        encrypted_files: The output files to be encrypted.
        post_processing_command: A command to fix up the ip sources.
    """
    encrypt_content = ""
    post_processing_command = ""
    encrypted_files = []
    for file in all_files:
        if file.extension in ["v", "sv"]:
            language = "verilog"
        elif file.extension in ["vhd", "vhdl"]:
            language = "vhdl"
        else:
            continue
        enc_extension = ".enc.{}".format(file.extension)
        enc_filename = "{}{}".format(file.basename.split(".")[0], enc_extension)
        encrypt_content += "encrypt -key {} -lang {} -ext {} {}\n".format(keyfile_path, language, enc_extension, file.path)
        enc_file = ctx.actions.declare_file(enc_filename)
        encrypted_files.append(enc_file)
        source_file = "{}/{}".format(file.dirname, enc_file.basename)
        post_processing_command += "cp {} {}; ".format(source_file, enc_file.path)
        post_processing_command += "cp {} {}/{}; ".format(source_file, ip_dir_src, file.basename)

    return [
        encrypt_content,
        encrypted_files,
        post_processing_command,
    ]
