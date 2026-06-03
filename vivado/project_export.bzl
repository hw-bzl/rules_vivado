"""# vivado_project_export rule."""

load("//vivado:providers.bzl", "VivadoProjectInfo")
load(
    "//vivado/private:common.bzl",
    "TOOLCHAIN_TYPE",
    "get_vivado_toolchain",
    "hook_attrs",
    "hook_invocation",
    "run_tcl_template",
    "tcl_list_literal",
    "tcl_script_attr",
    "tcl_script_data",
)

def _vivado_project_export_impl(ctx):
    toolchain = get_vivado_toolchain(ctx)

    project_info = ctx.attr.project[VivadoProjectInfo]

    # `outs` is an `attr.output_list`, so Bazel has already declared the
    # Files — `ctx.outputs.outs` hands them back. (`ctx.attr.outs` would
    # yield Labels, which `declare_file` rejects.)
    outs = ctx.outputs.outs
    out_dirs = [ctx.actions.declare_directory(d) for d in ctx.attr.out_dirs]

    script = tcl_script_data(ctx.attr.script[0])

    pre = hook_invocation(ctx, ctx.attr.pre_hooks, script = ctx.attr.script[0])
    post = hook_invocation(ctx, ctx.attr.post_hooks)

    substitutions = {
        "{{OUTS}}": tcl_list_literal([f.path for f in outs]),
        "{{OUT_DIRS}}": tcl_list_literal([d.path for d in out_dirs]),
        "{{POST_HOOKS}}": post.files_literal,
        "{{PRE_HOOKS}}": pre.files_literal,
        "{{PROJECT_TCL}}": project_info.project_tcl.path,
        "{{USER_SCRIPT}}": script.path,
    }

    input_files = (
        [project_info.project_tcl] +
        project_info.input_files.to_list()
    )

    run_tcl_template(
        ctx = ctx,
        toolchain = toolchain,
        template = ctx.file._driver_template,
        substitutions = substitutions,
        input_files = input_files,
        output_files = outs + out_dirs,
        mnemonic = "VivadoProjectExport",
        jobs = ctx.attr.jobs,
        tools = (
            project_info.hook_tools + pre.tools + post.tools + script.tools
        ),
    )

    return [DefaultInfo(files = depset(outs + out_dirs))]

vivado_project_export = rule(
    implementation = _vivado_project_export_impl,
    doc = """Run a user-provided Tcl script against a `vivado_project`, \
declaring the file and directory outputs the script produces.

Shaped like a `genrule`: you supply the Tcl and declare what it writes;
the rule sources the project's emitted TCL, sources your script, then
verifies every declared output exists. `script` takes an executable
target — in practice a `tcl_binary` — so the script can `package
require` shared `tcl_library` helpers.

Prefer a typed rule (`vivado_synthesis`, `vivado_export_simulation`,
`vivado_hw_platform`, …) whenever your workflow maps to one — this is
the escape hatch for workflows that map to none and don't justify a new
rule. Two consumers writing the same invocation with the same Tcl body
is the signal to promote it to a typed rule.

Project-input only: phases whose input is a checkpoint (`write_edif`,
`write_verilog`, `write_hw_platform`, …) do not fit this shape.

Provides only `DefaultInfo`, by design — escape-hatch consumers work off
file paths, not typed contracts.
""",
    attrs = {
        "jobs": attr.int(
            doc = "Jobs hint to Bazel's scheduler.",
            default = 1,
        ),
        "out_dirs": attr.string_list(
            doc = ("Declared TreeArtifact outputs. Each becomes a " +
                   "`ctx.actions.declare_directory`; paths land in " +
                   "`$OUT_DIRS` (Tcl list, in declared order). User's Tcl " +
                   "must ensure each directory exists at action completion."),
            default = [],
        ),
        "outs": attr.output_list(
            doc = ("Declared File outputs. Each becomes a " +
                   "`ctx.actions.declare_file`; paths land in `$OUTS` " +
                   "(Tcl list, in declared order). User's Tcl must ensure " +
                   "each file exists at action completion or Bazel fails " +
                   "the action."),
        ),
        "project": attr.label(
            doc = ("`vivado_project` target. The emitted project TCL is " +
                   "sourced BEFORE the user's Tcl, so the user script runs " +
                   "against a fully-loaded project."),
            providers = [VivadoProjectInfo],
            mandatory = True,
        ),
        "script": tcl_script_attr(
            doc = ("Executable target (a `tcl_binary`) whose script is " +
                   "sourced after `vivado_project`'s TCL loads. Sees " +
                   "`$OUTS`, `$OUT_DIRS`, and `$PROJECT_DIR` as pre-set " +
                   "variables. Its `tcl_library` deps are staged as " +
                   "runfiles and reached with `package require`. A bare " +
                   "`.tcl` file is not accepted; wrap it in a " +
                   "`tcl_binary`."),
        ),
        "_driver_template": attr.label(
            default = Label("//vivado/private:project_export.tcl.template"),
            allow_single_file = [".template"],
        ),
    } | hook_attrs(
        post_doc = ("`.tcl` files OR `tcl_binary` targets sourced after the " +
                    "user's Tcl completes. Sourced in list order."),
        pre_doc = ("`.tcl` files OR `tcl_binary` targets sourced after the " +
                   "project loads but BEFORE the user's Tcl. Sourced in " +
                   "list order."),
        extensions = [".tcl"],
    ),
    provides = [DefaultInfo],
    toolchains = [TOOLCHAIN_TYPE],
)
