"""# Simulation rule: xsim_test."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoIPBlockInfo")
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "generate_file_load_tcl",
    "generate_ip_block_tcl",
    "run_tcl_template",
)

def _xsim_test_impl(ctx):
    all_files, hdl_source_content, constraints_content, tcl_content = generate_file_load_tcl(ctx.attr.module)

    ip_block_tcl = generate_ip_block_tcl(ctx.attr.ip_blocks)
    ip_block_dirs = []
    for ip_block in ctx.attr.ip_blocks:
        ip_block_dirs += ip_block[VivadoIPBlockInfo].repo

    project_dir = ctx.actions.declare_directory("{}_prj".format(ctx.label.name))
    if (ctx.attr.with_waveform):
        with_waveform_str = "1"
        wave_db = ctx.actions.declare_file("{}.wdb".format(ctx.label.name))
        wave_db_path = wave_db.path
        outputs = [project_dir, wave_db]
    else:
        with_waveform_str = "0"
        wave_db_path = ""
        outputs = [project_dir]

    substitutions = {
        "{{CONSTRAINTS_CONTENT}}": constraints_content,
        "{{HDL_SOURCE_CONTENT}}": hdl_source_content,
        "{{IP_BLOCK_TCL}}": ip_block_tcl,
        "{{MODULE_TOP}}": ctx.attr.module_top,
        "{{PART_NUMBER}}": ctx.attr.part_number,
        "{{PROJECT_DIR}}": project_dir.path,
        "{{TCL_CONTENT}}": tcl_content,
        "{{WAVE_DB}}": wave_db_path,
        "{{WITH_WAVEFORM}}": with_waveform_str,
    }

    _, vivado_log, vivado_journal = run_tcl_template(
        ctx = ctx,
        template = ctx.file.xsim_test_template,
        substitutions = substitutions,
        input_files = all_files + ip_block_dirs,
        output_files = outputs,
        mnemonic = "VivadoXSim",
    )

    outputs.append(vivado_log)
    outputs.append(vivado_journal)

    log_runfiles = ctx.runfiles(files = [vivado_log])

    # Error detection script:
    # - Match "$error" output format: "Error: " (with colon and space)
    # - Match Vivado/xsim errors: "ERROR:" (uppercase)
    # - Match fatal errors: "FATAL" or "$fatal"
    # - Avoid false positives from module names containing "Error"
    error_parser = """#!/bin/bash
LOG_FILE="{log_file}"

# Check for simulation errors (case-sensitive patterns)
if grep -qE '^Error: |^ERROR:|FATAL_ERROR|\\$fatal' "$LOG_FILE"; then
    echo "=== Test FAILED - errors detected in simulation log ==="
    # Show relevant error lines
    grep -E '^Error: |^ERROR:|FATAL' "$LOG_FILE"
    exit 1
fi

# Check that simulation actually completed (look for $finish)
if ! grep -q '\\$finish' "$LOG_FILE"; then
    echo "=== Test FAILED - simulation did not complete (no \\$finish) ==="
    tail -50 "$LOG_FILE"
    exit 1
fi

echo "=== Test PASSED ==="
exit 0
""".format(log_file = vivado_log.short_path)

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = error_parser,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = log_runfiles,
            executable = ctx.outputs.executable,
        ),
    ]

xsim_test = rule(
    doc = "Run a Vivado xsim simulation as a Bazel test.",
    implementation = _xsim_test_impl,
    test = True,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "ip_blocks": attr.label_list(
            doc = "Ip blocks to include in this design.",
            providers = [VivadoIPBlockInfo],
            default = [],
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
        "with_waveform": attr.bool(
            doc = "Generate with a waveform",
            default = False,
        ),
        "xsim_test_template": attr.label(
            doc = "The tcl template to run on vivado.",
            default = Label("//vivado/private:xsim_test.tcl.template"),
            allow_single_file = [".template"],
        ),
    },
)
