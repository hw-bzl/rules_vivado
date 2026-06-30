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
    "generate_encrypt_tcl",
    "generate_file_load_tcl",
    "generate_ip_block_tcl",
    "run_tcl_template",
)

def _vivado_create_ip_impl(ctx):
    all_files, hdl_source_content, constraints_content, tcl_content = generate_file_load_tcl(ctx.attr.module)

    xci_name = ctx.label.name
    ip_dir = ctx.actions.declare_directory(ctx.label.name)
    ip_block_tcl = generate_ip_block_tcl(ctx.attr.ip_blocks)

    outputs = [ip_dir]

    post_processing_command = ""
    encrypt_content = ""
    ip_src_dir = "{}/src/".format(ip_dir.path)
    if ctx.attr.encrypt:
        encrypt_content, encrypted_files, post_processing_command = generate_encrypt_tcl(
            ctx = ctx,
            all_files = all_files,
            keyfile_path = ctx.file.keyfile.path,
            ip_dir_src = ip_src_dir,
        )
        outputs += encrypted_files

    substitutions = {
        "{{CONSTRAINTS_CONTENT}}": constraints_content,
        "{{ENCRYPT_CONTENT}}": encrypt_content,
        "{{HDL_SOURCE_CONTENT}}": hdl_source_content,
        "{{IP_BLOCK_TCL}}": ip_block_tcl,
        "{{IP_LIBRARY}}": ctx.attr.ip_library,
        "{{IP_OUTPUT_DIR}}": ip_dir.path,
        "{{IP_VENDOR}}": ctx.attr.ip_vendor,
        "{{IP_VERSION}}": ctx.attr.ip_version,
        "{{JOBS}}": "{}".format(ctx.attr.jobs),
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{PROJECT_DIR}}": "./",
        "{{TCL_CONTENT}}": tcl_content,
        "{{XCI_NAME}}": xci_name,
    }

    ip_block_dirs = []
    for ip_block in ctx.attr.ip_blocks:
        ip_block_dirs += ip_block[VivadoIPBlockInfo].repo
    ip_block_outputs = run_tcl_template(
        ctx = ctx,
        template = ctx.file.create_ip_block_template,
        substitutions = substitutions,
        input_files = all_files + [ctx.file.keyfile] + ip_block_dirs,
        output_files = outputs,
        mnemonic = "VivadoCreateIp",
        jobs = ctx.attr.jobs,
        post_processing_command = post_processing_command,
    )

    return [
        ip_block_outputs[0],
        VivadoIPBlockInfo(
            is_interface = False,
            repo = [ip_dir] + ip_block_dirs,
            vendor = ctx.attr.ip_vendor,
            library = ctx.attr.ip_library,
            version = ctx.attr.ip_version,
            module_top = ctx.attr.module_top,
        ),
    ]

vivado_create_ip = rule(
    implementation = _vivado_create_ip_impl,
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
    },
    provides = [
        DefaultInfo,
        VivadoIPBlockInfo,
    ],
)

def _vivado_interface_definition_impl(ctx):
    """Implementation of vivado_interface_definition rule.

    Uses two chained actions:
      1. Parse SV file -> signals JSON (overridable parser)
      2. Generate XML/TCL from JSON + templates (internal generator)
    """
    name = ctx.attr.interface_name
    vendor = ctx.attr.vendor
    library = ctx.attr.library
    version = ctx.attr.version

    sv_file = ctx.file.src
    parser = ctx.executable.parser
    generator = ctx.executable._generator

    signals_json = ctx.actions.declare_file("{}_signals.json".format(name))
    ctx.actions.run(
        executable = parser,
        arguments = ["--input", sv_file.path, "--output", signals_json.path],
        inputs = [sv_file],
        outputs = [signals_json],
        mnemonic = "VivadoParseInterface",
        progress_message = "Parsing SV interface %{label}",
        toolchain = TOOLCHAIN_TYPE,
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

def _vivado_create_interface_ip_impl(ctx):
    """Implementation of vivado_create_interface_ip rule."""
    interface_info = ctx.attr.interface[VivadoInterfaceInfo]

    ip_dir = ctx.actions.declare_directory(ctx.label.name)

    display_name = interface_info.name.replace("_", " ").title() + " Interface"
    description = ctx.attr.description if ctx.attr.description else display_name
    vendor_display_name = ctx.attr.vendor_display_name if ctx.attr.vendor_display_name else interface_info.vendor

    hdl_source_content = ""
    all_files = []
    if ctx.attr.module:
        all_files, hdl_source_content, _, _ = generate_file_load_tcl(ctx.attr.module)

    substitutions = {
        "{{ABSTRACTION_DEFINITION_BASENAME}}": interface_info.abstraction_definition.basename,
        "{{ABSTRACTION_DEFINITION_FILE}}": interface_info.abstraction_definition.path,
        "{{BUS_DEFINITION_BASENAME}}": interface_info.bus_definition.basename,
        "{{BUS_DEFINITION_FILE}}": interface_info.bus_definition.path,
        "{{DESCRIPTION}}": description,
        "{{DISPLAY_NAME}}": display_name,
        "{{HDL_SOURCE_CONTENT}}": hdl_source_content,
        "{{INTERFACE_NAME}}": interface_info.name,
        "{{IP_LIBRARY}}": interface_info.library,
        "{{IP_OUTPUT_DIR}}": ip_dir.path,
        "{{IP_VENDOR}}": interface_info.vendor,
        "{{IP_VERSION}}": interface_info.version,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{VENDOR_DISPLAY_NAME}}": vendor_display_name,
    }

    input_files = [
        interface_info.bus_definition,
        interface_info.abstraction_definition,
    ] + all_files

    outputs = [ip_dir]

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.create_interface_ip_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = outputs,
        mnemonic = "VivadoCreateInterfaceIp",
    )

    return [
        default_info[0],
        VivadoIPBlockInfo(
            is_interface = True,
            repo = [ip_dir],
            vendor = interface_info.vendor,
            library = interface_info.library,
            version = interface_info.version,
            module_top = interface_info.name,
        ),
    ]

vivado_create_interface_ip = rule(
    implementation = _vivado_create_interface_ip_impl,
    doc = "Package a Vivado interface definition as an IP block. Unlike vivado_create_ip, this does not require a top module.",
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "create_interface_ip_template": attr.label(
            doc = "The TCL template for creating interface IP.",
            default = Label("//vivado/private:create_interface_ip.tcl.template"),
            allow_single_file = [".template"],
        ),
        "description": attr.string(
            doc = "Description for the IP block.",
            default = "",
        ),
        "interface": attr.label(
            doc = "The interface definition to package.",
            providers = [VivadoInterfaceInfo],
            mandatory = True,
        ),
        "module": attr.label(
            doc = "The verilog_library containing the interface source file(s).",
            providers = [[VerilogInfo], [VhdlInfo]],
        ),
        "part_number": attr.string(
            doc = "The targeted xilinx part.",
            mandatory = True,
        ),
        "vendor_display_name": attr.string(
            doc = "Display name for the vendor.",
            default = "",
        ),
    },
    provides = [
        DefaultInfo,
        VivadoIPBlockInfo,
    ],
)
