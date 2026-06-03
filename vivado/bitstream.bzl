"""# Bitstream-phase rule: vivado_bitstream."""

load("//vivado:providers.bzl", "VivadoLogInfo", "VivadoRoutingCheckpointInfo")
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "run_tcl_template",
    "tcl_args",
    "validate_args",
)

_TIMING_CHECK_VALUES = ["error", "warn", "none"]

def _timing_check_attr(cmd):
    """Return the shared `timing_check` attr.

    Gating a write on post-route timing is a house-style policy call, not
    something Vivado imposes — some shops ship known-failing bring-up
    images, others treat any negative slack as a hard stop. Exposing it as
    an attr means changing the policy doesn't require forking the
    template.

    Args:
        cmd (str): the Vivado command name named in the doc string.

    Returns:
        Attribute: an `attr.string` for the rule's `attrs`.
    """
    return attr.string(
        doc = ("Policy for post-route timing violations. Both setup (WNS) " +
               "and hold (WHS) worst slack are probed. `error` (default) " +
               "fails the action; `warn` logs a CRITICAL WARNING and runs " +
               "`{}` anyway; `none` skips the gate entirely. A design with " +
               "no post-route timing paths at all is always treated as " +
               "unconstrained (warning, not failure).").format(cmd),
        default = "error",
        values = _TIMING_CHECK_VALUES,
    )

def _vivado_bitstream_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    bitstream = ctx.actions.declare_file("{}.bit".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoRoutingCheckpointInfo].checkpoint

    outputs = [bitstream]

    # The rule owns overwrite policy (`-force`) and the output path (the
    # positional arg is the declared `.bit`); letting `write_args` respell
    # either would break the "Bazel-declared output is always produced"
    # contract.
    validate_args(
        ctx.label,
        "write_args",
        ctx.attr.write_args,
        ["-force", "-file"],
    )

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    substitutions = {
        "{{BITSTREAM}}": bitstream.path,
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_CHECK}}": ctx.attr.timing_check,
        "{{WRITE_ARGS}}": tcl_args(ctx.attr.write_args),
    }

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.write_bitstream_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoWriteBitstream",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs["write_bitstream"] = result.log
    journals["write_bitstream"] = result.journal

    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoLogInfo(logs = logs, journals = journals),
        # `tcl` output group exposes the rendered TCL script for
        # `bazel build //foo:x --output_groups=tcl`. Bitstream rules
        # have no primary provider to carry it (unlike synth/place/route);
        # OutputGroupInfo is the natural home.
        OutputGroupInfo(
            log = depset(logs.values()),
            tcl = depset([result.vivado_tcl]),
        ),
    ]

vivado_bitstream = rule(
    doc = ("Write a Vivado bitstream (.bit) from a routed checkpoint. For " +
           "the `.xsa` hardware-platform handoff artifact, compose " +
           "`vivado_hw_platform` on the same checkpoint."),
    implementation = _vivado_bitstream_impl,
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
        "timing_check": _timing_check_attr("write_bitstream"),
        "write_args": attr.string_list(
            doc = ("Extra flags passed through to `write_bitstream`. Cannot " +
                   "contain `-force` (always emitted by the rule) or `-file` " +
                   "(the rule's declared output path is the positional arg)."),
            default = [],
        ),
        "write_bitstream_template": attr.label(
            doc = "The write bitstream tcl template",
            default = Label("//vivado/private:write_bitstream.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after a successful `write_bitstream`, in list order."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened checkpoint before `write_bitstream`."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
    ],
)

def _vivado_device_image_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    device_image = ctx.actions.declare_file("{}.pdi".format(ctx.label.name))

    checkpoint_in = ctx.attr.checkpoint[VivadoRoutingCheckpointInfo].checkpoint

    outputs = [device_image]

    pre = hook_invocation(ctx, ctx.attr.pre_hooks)
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    # Reject `-no_pdi` in `write_args` — the dedicated `no_pdi` attr owns
    # that flag because it also shifts responsibility for producing the
    # declared `.pdi` output onto `post_hooks`. Two ways to spell the
    # same thing lets a `write_args = ["-no_pdi"]` caller silently break
    # the "Bazel-declared output is always produced" contract.
    validate_args(
        ctx.label,
        "write_args",
        ctx.attr.write_args,
        ["-force", "-file", "-no_pdi"],
    )

    substitutions = {
        "{{CHECKPOINT_IN}}": checkpoint_in.path,
        "{{DEVICE_IMAGE}}": device_image.path,
        "{{NO_PDI}}": "1" if ctx.attr.no_pdi else "0",
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{THREADS}}": "{}".format(ctx.attr.threads),
        "{{TIMING_CHECK}}": ctx.attr.timing_check,
        "{{WRITE_ARGS}}": tcl_args(ctx.attr.write_args),
    }

    result = run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file.write_device_image_template,
        substitutions = substitutions,
        input_files = [checkpoint_in],
        output_files = outputs,
        mnemonic = "VivadoWriteDeviceImage",
        jobs = ctx.attr.threads,
        tools = pre.tools + post.tools,
    )

    upstream = ctx.attr.checkpoint[VivadoLogInfo]
    logs = dict(upstream.logs)
    journals = dict(upstream.journals)
    logs["write_device_image"] = result.log
    journals["write_device_image"] = result.journal

    # `tcl` exposes the rendered TCL script (device_image rules have no
    # primary provider to carry it).
    output_groups = {
        "log": depset(logs.values()),
        "pdi": depset([device_image]),
        "tcl": depset([result.vivado_tcl]),
    }
    return [
        DefaultInfo(files = depset(result.outputs)),
        VivadoLogInfo(logs = logs, journals = journals),
        OutputGroupInfo(**output_groups),
    ]

vivado_device_image = rule(
    doc = ("Write a Versal device image (.pdi) from a routed checkpoint. " +
           "For non-Versal architectures use `vivado_bitstream` instead. " +
           "For the `.xsa` hardware-platform handoff artifact, compose " +
           "`vivado_hw_platform` on the same checkpoint."),
    implementation = _vivado_device_image_impl,
    toolchains = [TOOLCHAIN_TYPE],
    attrs = {
        "checkpoint": attr.label(
            doc = "Routed checkpoint.",
            providers = [VivadoRoutingCheckpointInfo],
            mandatory = True,
        ),
        "no_pdi": attr.bool(
            doc = (
                "Skip Vivado's internal bootgen wrap and shift " +
                "PDI-production to `post_hooks`. When True, Vivado runs " +
                "`write_device_image` with `-no_pdi` — only the " +
                "intermediate `.rcdo` / `.rnpi` files (base name = " +
                "`$env(VIVADO_PDI_INTERMEDIATE_BASE)`) plus a `gen_files/` " +
                "directory are emitted. A `post_hooks` entry MUST " +
                "produce the final `.pdi` at `$env(VIVADO_PDI_OUT)` " +
                "(typically via `exec bootgen -arch versal -image <BIF> " +
                "-w -o $env(VIVADO_PDI_OUT)`); Bazel fails the action if " +
                "the file is missing. Both paths are exported as " +
                "process env vars so hooks read them via the standard " +
                "`$env(...)` channel without depending on Tcl globals " +
                "the caller can't see. Note: the resulting 'declared " +
                "output was not created' error surfaces at the rule " +
                "level, not the hook, so hook authors need to know they " +
                "own the PDI when this is set."
            ),
            default = False,
        ),
        "threads": attr.int(
            doc = "Threads to pass to vivado which defines the amount of parallelism.",
            default = 8,
        ),
        "timing_check": _timing_check_attr("write_device_image"),
        "write_args": attr.string_list(
            doc = ("Extra flags passed through to `write_device_image`. Cannot " +
                   "contain `-force` (always emitted by the rule), `-file` " +
                   "(the rule's declared output path is the positional arg), " +
                   "or `-no_pdi` (use the dedicated `no_pdi` attr)."),
            default = [],
        ),
        "write_device_image_template": attr.label(
            doc = "The write device image tcl template",
            default = Label("//vivado/private:write_device_image.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                    "sourced after a successful `write_device_image`, in " +
                    "list order. When `no_pdi = True`, at least one " +
                    "post_hook MUST produce the final `.pdi` at " +
                    "`$env(VIVADO_PDI_OUT)`."),
        pre_doc = ("`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets " +
                   "sourced on the opened checkpoint before `write_device_image`."),
    ),
    provides = [
        DefaultInfo,
        VivadoLogInfo,
    ],
)
