"""vivado_create_project rule: build a Vivado project without synthesizing."""

load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoIPBlockInfo")
load(
    "//vivado/private:common.bzl",
    "OPTIONAL_TOOLCHAIN",
    "XILINX_ENV_ATTR",
    "create_and_synth",
)

def _vivado_create_project_impl(ctx):
    default_info = create_and_synth(ctx = ctx, with_synth = 0)
    return [default_info[0]]

vivado_create_project = rule(
    implementation = _vivado_create_project_impl,
    doc = "Create a Vivado project from a verilog_library without running synthesis.",
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
    } | XILINX_ENV_ATTR,
)
