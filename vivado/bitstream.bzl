"""# Bitstream-phase rule: vivado_write_bitstream."""

load("//vivado:providers.bzl", "VivadoRoutingCheckpointInfo")
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "run_tcl_template",
)

def _vivado_write_bitstream_impl(ctx):
    bitstream = ctx.actions.declare_file("{}.bit".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoRoutingCheckpointInfo].checkpoint

    outputs = [bitstream]

    if ctx.attr.with_xsa:
        with_xsa_str = "1"
        xsa_out = ctx.actions.declare_file("{}.xsa".format(ctx.label.name))
        xsa_path = xsa_out.path
        outputs.append(xsa_out)
    else:
        with_xsa_str = "0"
        xsa_path = "nothing.xsa"

    substitutions = {
        "{{BITSTREAM}}": bitstream.path,
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{WRITE_XSA}}": with_xsa_str,
        "{{XSA_PATH}}": xsa_path,
    }

    default_info = run_tcl_template(
        ctx = ctx,
        template = ctx.file.write_bitstream_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoWriteBitstream",
        jobs = ctx.attr.threads,
    )
    return [default_info[0]]

vivado_write_bitstream = rule(
    doc = "Write a Vivado bitstream (.bit) from a routed checkpoint, optionally including a .xsa.",
    implementation = _vivado_write_bitstream_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Routed checkpoint.",
            providers = [VivadoRoutingCheckpointInfo],
            mandatory = True,
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
        "with_xsa": attr.bool(
            doc = "Generate xsa too",
            default = False,
        ),
        "write_bitstream_template": attr.label(
            doc = "The write bitstream tcl template",
            default = Label("//vivado/private:write_bitstream.tcl.template"),
            allow_single_file = [".template"],
        ),
    },
    provides = [
        DefaultInfo,
    ],
)
