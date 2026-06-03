"""# IP packaging rules"""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load(
    "//vivado:providers.bzl",
    "VivadoIPBlockInfo",
    "VivadoInterfaceInfo",
)
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "encrypt_data",
    "get_vivado_toolchain",
    "hdl_sources_data",
    "hook_attrs",
    "hook_invocation",
    "ip_blocks_data",
    "project_hooks_attr",
    "run_tcl_template",
    "tcl_script_attr",
    "tcl_script_data",
)

def _vivado_ip_core_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    hdl = hdl_sources_data(ctx.attr.module)
    ip = ip_blocks_data(ctx.attr.ip_blocks)

    xci_name = ctx.label.name
    ip_dir = ctx.actions.declare_directory(ctx.label.name)

    outputs = [ip_dir]

    post_processing_command = ""
    if ctx.attr.encrypt:
        enc = encrypt_data(
            ctx = ctx,
            all_files = hdl.all_files,
            ip_dir_src = "{}/src/".format(ip_dir.path),
        )
        encrypt_files_literal = enc.encrypt_files
        outputs += enc.encrypted_outputs
        post_processing_command = enc.post_processing_command
    else:
        encrypt_files_literal = "{}"

    substitutions = {
        "{{ENCRYPT_FILES}}": encrypt_files_literal,
        "{{ENCRYPT_KEYFILE}}": ctx.file.keyfile.path,
        "{{HDL_SOURCES}}": hdl.hdl_sources,
        "{{IP_CONFIGURED_INSTANCES}}": ip.ip_configured_instances,
        "{{IP_INSTANCES}}": ip.ip_instances,
        "{{IP_LIBRARY}}": ctx.attr.ip_library,
        "{{IP_OUTPUT_DIR}}": ip_dir.path,
        "{{IP_REPOS}}": ip.ip_repos,
        "{{IP_VENDOR}}": ctx.attr.ip_vendor,
        "{{IP_VERSION}}": ctx.attr.ip_version,
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{PROJECT_DIR}}": "./",
        "{{SRC_DIRS}}": hdl.src_dirs,
        "{{SUPPORTED_FAMILIES}}": " ".join(ctx.attr.supported_families),
        "{{TCL_FILES}}": hdl.tcl_files,
        "{{XCI_NAME}}": xci_name,
        "{{XDC_FILES}}": hdl.xdc_files,
    }

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.create_ip_block_template,
        substitutions = substitutions,
        input_files = hdl.all_files + [ctx.file.keyfile] + ip.input_files,
        output_files = outputs,
        mnemonic = "VivadoCreateIp",
        jobs = ctx.attr.jobs,
        post_processing_command = post_processing_command,
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoIPBlockInfo(
            repo = [ip_dir] + ip.input_files,
            configured_instance = None,
            instantiable = struct(
                vendor = ctx.attr.ip_vendor,
                library = ctx.attr.ip_library,
                name = ctx.attr.module_top,
                version = ctx.attr.ip_version,
                module_name = ctx.attr.module_top + "_ip",
            ),
            # `project_hooks` don't fire in THIS IP's Vivado action; they
            # contribute to any downstream `vivado_project` that folds
            # this IP in via `ip_blocks`. The project's impl passes the
            # merged Target list through `hook_invocation`.
            project_hooks = ctx.attr.project_hooks,
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["module", "ip_blocks"],
        ),
    ]

vivado_ip_core = rule(
    implementation = _vivado_ip_core_impl,
    doc = "Use vivado to package a module into an IP core",
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "create_ip_block_template": attr.label(
            doc = "The create project tcl template",
            default = Label("//vivado/private:create_ip_block.tcl.template"),
            allow_single_file = [".template"],
        ),
        "encrypt": attr.bool(
            doc = "Encrypt the sources. Note: This requires a license. See: https://support.xilinx.com/s/article/68071?language=en_US",
            default = False,
        ),
        "ip_blocks": attr.label_list(
            doc = "Ip blocks to include in this design.",
            providers = [VivadoIPBlockInfo],
            default = [],
        ),
        "ip_library": attr.string(
            doc = "The version of this ip core.",
            mandatory = True,
        ),
        "ip_vendor": attr.string(
            doc = "The version of this ip core.",
            mandatory = True,
        ),
        "ip_version": attr.string(
            doc = "The version of this ip core.",
            mandatory = True,
        ),
        "jobs": attr.int(
            doc = "Jobs to pass to vivado which defines the amount of parallelism.",
            default = 4,
        ),
        "keyfile": attr.label(
            doc = "The keyfile to use when optionally encrypting",
            default = Label("//vivado/private:xilinx_keyfile.txt"),
            allow_single_file = [".txt"],
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
        "project_hooks": project_hooks_attr(),
        "supported_families": attr.string_list(
            doc = ("Xilinx device families this IP can be consumed by " +
                   "(e.g. `[\"zynq\", \"zynquplus\", \"versal\"]`). Each " +
                   "entry is registered at `Production` lifecycle. Leave " +
                   "empty to keep whatever `ipx::package_project` inferred " +
                   "from `part_number` — which restricts downstream " +
                   "consumers to the same family and produces " +
                   "`[Coretcl 2-1132] No IP matching VLNV ... is accessible " +
                   "for the current part '<other-family-part>'` when the " +
                   "consumer sits on a different family."),
            default = [],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    provides = [
        DefaultInfo,
        VivadoIPBlockInfo,
    ],
)

def _vivado_interface_definition_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    name = ctx.attr.interface_name
    vendor = ctx.attr.vendor
    library = ctx.attr.library
    version = ctx.attr.version

    sv_file = ctx.file.src
    parser = ctx.executable.parser
    generator = ctx.executable._generator
    toolchain_env = toolchain.env

    signals_json = ctx.actions.declare_file("{}_signals.json".format(name))
    ctx.actions.run(
        executable = parser,
        arguments = ["--input", sv_file.path, "--output", signals_json.path],
        inputs = [sv_file],
        outputs = [signals_json],
        mnemonic = "VivadoParseInterface",
        progress_message = "Parsing SV interface %{label}",
        toolchain = TOOLCHAIN_TYPE,
        env = toolchain_env,
    )

    bus_def_file = ctx.actions.declare_file("{}.xml".format(name))
    abs_def_file = ctx.actions.declare_file("{}_rtl.xml".format(name))
    setup_tcl_file = ctx.actions.declare_file("{}_if_setup.tcl".format(name))

    description = ctx.attr.description if ctx.attr.description else ""

    ctx.actions.run(
        executable = generator,
        arguments = [
            "--signals-json",
            signals_json.path,
            "--bus-def-template",
            ctx.file.bus_definition_template.path,
            "--abs-def-template",
            ctx.file.abstraction_definition_template.path,
            "--setup-tcl-template",
            ctx.file.interface_setup_template.path,
            "--bus-def-output",
            bus_def_file.path,
            "--abs-def-output",
            abs_def_file.path,
            "--setup-tcl-output",
            setup_tcl_file.path,
            "--vendor",
            vendor,
            "--library",
            library,
            "--name",
            name,
            "--version",
            version,
            "--direct-connection",
            "true" if ctx.attr.direct_connection else "false",
            "--is-addressable",
            "true" if ctx.attr.is_addressable else "false",
            "--max-masters",
            str(ctx.attr.max_masters),
            "--max-slaves",
            str(ctx.attr.max_slaves),
            "--description",
            description,
        ],
        inputs = [
            signals_json,
            ctx.file.bus_definition_template,
            ctx.file.abstraction_definition_template,
            ctx.file.interface_setup_template,
        ],
        outputs = [bus_def_file, abs_def_file, setup_tcl_file],
        mnemonic = "VivadoGenInterfaceXml",
        progress_message = "Generating IP-XACT XML %{label}",
        toolchain = TOOLCHAIN_TYPE,
        env = toolchain_env,
    )

    outputs = [bus_def_file, abs_def_file, setup_tcl_file]

    return [
        DefaultInfo(files = depset(outputs)),
        VivadoInterfaceInfo(
            name = name,
            vendor = vendor,
            library = library,
            version = version,
            bus_definition = bus_def_file,
            abstraction_definition = abs_def_file,
            setup_tcl = setup_tcl_file,
        ),
    ]

vivado_interface_definition = rule(
    implementation = _vivado_interface_definition_impl,
    doc = "Generate Vivado IP-XACT interface definition files (bus definition and abstraction definition XML).",
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "abstraction_definition_template": attr.label(
            doc = "The abstraction definition XML template.",
            default = Label("//vivado/private:abstraction_definition.xml.template"),
            allow_single_file = [".template"],
        ),
        "bus_definition_template": attr.label(
            doc = "The bus definition XML template.",
            default = Label("//vivado/private:bus_definition.xml.template"),
            allow_single_file = [".template"],
        ),
        "description": attr.string(
            doc = "Description for the interface.",
            default = "",
        ),
        "direct_connection": attr.bool(
            doc = "Whether direct connections are allowed.",
            default = True,
        ),
        "interface_name": attr.string(
            doc = "The name of the interface (e.g., 'hbm_reader').",
            mandatory = True,
        ),
        "interface_setup_template": attr.label(
            doc = "The interface setup TCL template.",
            default = Label("//vivado/private:interface_setup.tcl.template"),
            allow_single_file = [".template"],
        ),
        "is_addressable": attr.bool(
            doc = "Whether the interface is addressable.",
            default = True,
        ),
        "library": attr.string(
            doc = "The library VLNV component (e.g., 'interface').",
            default = "interface",
        ),
        "max_masters": attr.int(
            doc = "Maximum number of masters.",
            default = 1,
        ),
        "max_slaves": attr.int(
            doc = "Maximum number of slaves.",
            default = 1,
        ),
        "parser": attr.label(
            doc = "Python parser script (SV -> JSON). Override to customize SV parsing.",
            default = Label("//vivado/private:parse_sv_interface"),
            cfg = "exec",
            executable = True,
        ),
        "src": attr.label(
            doc = "The SystemVerilog interface source file to parse.",
            mandatory = True,
            allow_single_file = [".sv"],
        ),
        "vendor": attr.string(
            doc = "The vendor VLNV component (e.g., 'mycompany.com').",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The version VLNV component (e.g., '1.0').",
            default = "1.0",
        ),
        "_generator": attr.label(
            default = Label("//vivado/private:generate_interface_xml"),
            cfg = "exec",
            executable = True,
        ),
    },
    provides = [
        DefaultInfo,
        VivadoInterfaceInfo,
    ],
)

def _vivado_interface_ip_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    interface_info = ctx.attr.interface[VivadoInterfaceInfo]

    ip_dir = ctx.actions.declare_directory(ctx.label.name)

    all_files = []
    if ctx.attr.module:
        hdl = hdl_sources_data(ctx.attr.module)
        all_files = hdl.all_files

    substitutions = {
        "{{ABSTRACTION_DEFINITION_FILE}}": interface_info.abstraction_definition.path,
        "{{BUS_DEFINITION_FILE}}": interface_info.bus_definition.path,
        "{{IP_OUTPUT_DIR}}": ip_dir.path,
    }

    input_files = [
        interface_info.bus_definition,
        interface_info.abstraction_definition,
    ] + all_files

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.create_interface_ip_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = [ip_dir],
        mnemonic = "VivadoCreateInterfaceIp",
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoIPBlockInfo(
            repo = [ip_dir],
            configured_instance = None,
            instantiable = None,
            project_hooks = [],
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["module"],
        ),
    ]

vivado_interface_ip = rule(
    implementation = _vivado_interface_ip_impl,
    doc = "Package a Vivado interface definition as an IP block. Unlike vivado_ip_core, this does not require a top module.",
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "create_interface_ip_template": attr.label(
            doc = "The TCL template for creating interface IP.",
            default = Label("//vivado/private:create_interface_ip.tcl.template"),
            allow_single_file = [".template"],
        ),
        "interface": attr.label(
            doc = "The interface definition to package.",
            providers = [VivadoInterfaceInfo],
            mandatory = True,
        ),
        "module": attr.label(
            doc = ("The `verilog_library` / `vhdl_library` containing the " +
                   "interface source file(s). Optional. The default " +
                   "template doesn't read these — Vivado discovers bus and " +
                   "abstraction definitions from the repo path alone — but " +
                   "the transitive sources are staged into the action " +
                   "sandbox so a caller-supplied " +
                   "`create_interface_ip_template` can, and so the " +
                   "interface's HDL shows up in coverage instrumentation."),
            providers = [[VerilogInfo], [VhdlInfo]],
        ),
    },
    provides = [
        DefaultInfo,
        VivadoIPBlockInfo,
    ],
)

def _vivado_xci_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    ip_dir = ctx.actions.declare_directory(ctx.label.name)
    verilog_dir = ctx.actions.declare_directory(ctx.label.name + ".verilog")
    vhdl_dir = ctx.actions.declare_directory(ctx.label.name + ".vhdl")
    verilog_header_dir = ctx.actions.declare_directory(ctx.label.name + ".verilog_header")
    data_dir = ctx.actions.declare_directory(ctx.label.name + ".data")

    pre = hook_invocation(ctx, ctx.attr.pre_hooks, script = ctx.attr.script[0])
    post = hook_invocation(ctx, ctx.attr.post_hooks)
    ip = ip_blocks_data(ctx.attr.ip_blocks)
    script = tcl_script_data(ctx.attr.script[0])

    substitutions = {
        "{{IP_CONFIGURED_INSTANCES}}": ip.ip_configured_instances,
        "{{IP_DIR}}": ip_dir.path,
        "{{IP_INSTANCES}}": ip.ip_instances,
        "{{IP_REPOS}}": ip.ip_repos,
        "{{IP_SCRIPT}}": script.path,
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
    }

    # After Vivado writes $IP_DIR, `sort_script` splits it into four
    # categorized sibling TreeArtifacts by extension. The original
    # `$IP_DIR` stays intact so `VivadoIPBlockInfo.configured_instance`
    # consumers can still locate `${module_top}.xci` at its known path;
    # the categorized dirs are the shape `VerilogInfo` / `VhdlInfo`
    # consumers reach through `deps`.
    sort_script = ctx.executable._sort_script
    post_processing_command = (
        "\"{script}\" --ip-dir \"{ip_dir}\" " +
        "--verilog-dir \"{verilog}\" " +
        "--verilog-header-dir \"{vhdr}\" " +
        "--vhdl-dir \"{vhdl}\" " +
        "--data-dir \"{data}\"\n"
    ).format(
        script = sort_script.path,
        ip_dir = ip_dir.path,
        verilog = verilog_dir.path,
        vhdl = vhdl_dir.path,
        vhdr = verilog_header_dir.path,
        data = data_dir.path,
    )

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.xci_template,
        substitutions = substitutions,
        input_files = ip.input_files + ctx.files.data,
        output_files = [ip_dir, verilog_dir, vhdl_dir, verilog_header_dir, data_dir],
        mnemonic = "VivadoXci",
        jobs = ctx.attr.jobs,
        tools = (
            pre.tools + post.tools + script.tools +
            [ctx.attr._sort_script[DefaultInfo].files_to_run]
        ),
        post_processing_command = post_processing_command,
    )

    # Cross-language wiring: an XCI IP typically ships both Verilog and
    # VHDL under the same package. When a consumer reaches this target
    # through `verilog_library.deps` we only surface `VerilogInfo`, so
    # the VHDL side has to ride along on `VerilogInfo.vhdl_deps` (and
    # symmetric on the VHDL side) — otherwise half the IP disappears
    # depending on which language the consuming library was written in.
    # Build leaf providers first (no cross-links), then reference their
    # depset fields directly from the returned providers so the combined
    # and leaf views point at one canonical source set. Downstream
    # `hdl_sources_data` dedupes by directory path, so consumers that
    # pull both providers directly (via `module = ":my_xci"`) don't
    # double-add the shared dirs.
    leaf_verilog = VerilogInfo(
        srcs = depset([verilog_dir]),
        hdrs = depset([verilog_header_dir]),
        data = depset([data_dir]),
    )
    leaf_vhdl = VhdlInfo(
        srcs = depset([vhdl_dir]),
        data = depset([data_dir]),
    )

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoIPBlockInfo(
            repo = [ip_dir] + ip.input_files,
            configured_instance = struct(
                repo_dir = ip_dir,
                xci_relpath = ctx.attr.module_top + ".xci",
                module_top = ctx.attr.module_top,
            ),
            instantiable = None,
            # `project_hooks` don't fire in THIS XCI's Vivado action;
            # they contribute to any downstream `vivado_project` that
            # folds this XCI in via `ip_blocks`. The project's impl
            # passes the merged Target list through `hook_invocation`.
            project_hooks = ctx.attr.project_hooks,
        ),
        VerilogInfo(
            srcs = leaf_verilog.srcs,
            hdrs = leaf_verilog.hdrs,
            data = leaf_verilog.data,
            vhdl_deps = depset([leaf_vhdl]),
        ),
        VhdlInfo(
            srcs = leaf_vhdl.srcs,
            data = leaf_vhdl.data,
            verilog_deps = depset([leaf_verilog]),
        ),
    ]

vivado_xci = rule(
    doc = """Package a Xilinx-catalog IP from a configuration TCL into a \
consumable IP repo.

`script` is the configuration script sourced inside a fresh Vivado
project. It must call
`create_ip -name <ip> -vendor xilinx.com -library ip -version <ver> \\
    -module_name <module_top> -dir . -force` and (optionally) configure
the IP via `set_property -dict {...} [get_ips <module_top>]`. The attr
takes an executable target — in practice a `tcl_binary`, which is what
carries the `deps` a script needs to `package require` shared
`tcl_library` helpers. An extra-toolchains transition routes it through
the Vivado tcl toolchain, so its wrapper comes out as a `.vhook.tcl`
Vivado can source directly and its deps land on `auto_path`.

The resulting `.xci` plus generated HDL/sim files are captured into a
TreeArtifact directory and exposed via `VivadoIPBlockInfo` so the IP
repo is auto-added to the consumer's `ip_repo_paths`.

Alongside `VivadoIPBlockInfo`, the rule also exposes `VerilogInfo` and
`VhdlInfo` so the target is `deps`-interchangeable with `verilog_library`
and `vhdl_library`. Generated files are split by extension into four
sibling TreeArtifacts — `<name>.verilog` (`.v` / `.sv`), `<name>.vhdl`
(`.vhd` / `.vhdl`), `<name>.verilog_header` (`.vh` / `.svh`), and
`<name>.data` (everything else) — which are placed on the appropriate
`srcs` / `hdrs` / `data` fields of the two providers. Consuming rules
add each directory via `add_files`; Vivado auto-classifies files
inside by extension. The split carries the IP's `sim/` behavioural model
and `hdl/` sources; the `synth/` wrapper (a second definition of the same
module) and copies of upstream `ip_blocks` are left out, so a
`verilog_library`-shaped consumer sees each module exactly once. Vivado
flows should consume the IP through `ip_blocks` (the `.xci`) rather than
through these directories.

Use the `ip_blocks` attribute on `vivado_project`, `vivado_block_design`,
or `vivado_ip_core` to make this IP available to that consumer. BD
cells that reference the IP's VLNV (e.g.
`create_bd_cell -vlnv xilinx.com:ip:axi_dma:7.1`) will then resolve via
the catalog.

For your own HDL packaged as a new reusable IP, use `vivado_ip_core`
instead.
""",
    implementation = _vivado_xci_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "data": attr.label_list(
            doc = ("Additional files the IP-config TCL needs available in " +
                   "the action's sandbox. Each file is materialized at its " +
                   "workspace-relative path; the TCL can reference it via " +
                   "that path (e.g., to `exec patch -i ...` against the " +
                   "generated HDL, or to `read` a side data file). Same " +
                   "semantics as `cc_library.data`, `py_test.data`, etc."),
            allow_files = True,
            default = [],
        ),
        "ip_blocks": attr.label_list(
            doc = "Other IP blocks the configuration TCL depends on (rare; mostly empty).",
            providers = [VivadoIPBlockInfo],
            default = [],
        ),
        "jobs": attr.int(
            doc = "Jobs to pass to vivado (resource hint to Bazel's scheduler).",
            default = 1,
        ),
        "module_top": attr.string(
            doc = "The `module_name` passed to `create_ip` in `script`. Used to locate the produced `.xci`.",
            mandatory = True,
        ),
        "part_number": attr.string(
            doc = "Xilinx part number the IP is configured for.",
            mandatory = True,
        ),
        "project_hooks": project_hooks_attr(),
        "script": tcl_script_attr(
            doc = ("Executable target (a `tcl_binary`) whose script is " +
                   "sourced inside a fresh Vivado project to configure the " +
                   "IP. Must call `create_ip ... -module_name " +
                   "<module_top>`. Its `tcl_library` deps are staged as " +
                   "runfiles and reached with `package require`. A bare " +
                   "`.tcl` file is not accepted; wrap it in a " +
                   "`tcl_binary`."),
        ),
        "xci_template": attr.label(
            doc = "The XCI tcl template.",
            default = Label("//vivado/private:create_xci.tcl.template"),
            allow_single_file = [".template"],
        ),
        "_sort_script": attr.label(
            doc = ("Splits the generated IP tree into the four " +
                   "per-language sibling TreeArtifacts. Invoked as " +
                   "`sort_xci_outputs.sh --ip-dir <in> --verilog-dir <out> " +
                   "--verilog-header-dir <out> --vhdl-dir <out> " +
                   "--data-dir <out>`."),
            default = Label("//vivado/private:sort_xci_outputs"),
            cfg = "exec",
            executable = True,
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after `generate_target`, before the project " +
                    "closes. Sourced in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced after project + IP-block setup, before sourcing " +
                   "the user IP TCL. Sourced in list order."),
    ),
    provides = [
        DefaultInfo,
        VerilogInfo,
        VhdlInfo,
        VivadoIPBlockInfo,
    ],
)
