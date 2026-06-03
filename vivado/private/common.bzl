"""Shared helpers used by every vivado rule.

Helpers return DATA (Tcl list / dict literals) for substitution into rule
templates. Templates own all Tcl code; rules emit only data.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_tcl//tcl:tcl_info.bzl", "TclInfo")
load("@rules_verilog//verilog:defs.bzl", "VerilogInfo")
load("@rules_vhdl//vhdl:defs.bzl", "VhdlInfo")
load("//vivado:providers.bzl", "VivadoBlockDesignInfo", "VivadoIPBlockInfo")
load("//vivado:toolchain.bzl", _TOOLCHAIN_TYPE = "TOOLCHAIN_TYPE")
load(":resource_set.bzl", "get_resource_set")
load(":transitions.bzl", "hook_transition")

TOOLCHAIN_TYPE = _TOOLCHAIN_TYPE

# ============================================================================
# Tcl literal formatting
# ============================================================================

def _tcl_list(items):
    """Format `items` as a Tcl list literal.

    Empty elements are encoded as `{}` so positional Tcl `lassign` still gets
    the right slot count.
    """
    if not items:
        return "{}"
    return "{ " + " ".join([i if i != "" else "{}" for i in items]) + " }"

def tcl_list_literal(items):
    """Public wrapper of `_tcl_list` for rule files that build Tcl list literals."""
    return _tcl_list(items)

def _tcl_tuples(rows):
    """Format a list-of-lists as Tcl `{{a b c} {d e f}}`."""
    if not rows:
        return "{}"
    return "{ " + " ".join([_tcl_list(r) for r in rows]) + " }"

def _tcl_dict(pairs):
    """Format `pairs` as a `[dict create ...]` Tcl expression."""
    parts = []
    for k, v in pairs:
        parts.append("{} {{{}}}".format(k, v))
    return "[dict create " + " ".join(parts) + "]"

# ============================================================================
# Pass-through CLI args (`synth_args`, `place_args`, …)
# ============================================================================

def tcl_args(args):
    """Format a starlark `string_list` as a brace-quoted Tcl word list.

    Items containing whitespace are brace-wrapped so they survive Tcl list
    parsing as a single token. Literal Tcl quoting metacharacters
    (`{`, `}`, `\\`, `"`) must be brace-quoted by the caller.

    Args:
        args (list[str]): CLI args; may be empty.

    Returns:
        str: a Tcl word-list literal.
    """
    if not args:
        return "{}"
    out = []
    for a in args:
        if " " in a or "\t" in a:
            out.append("{" + a + "}")
        else:
            out.append(a)
    return "{ " + " ".join(out) + " }"

def validate_args(label, attr_name, args, forbidden):
    """Fail loudly if user-supplied args contain rule-controlled flags.

    Templates also emit user args BEFORE the rule's flags
    (`<cmd> {*}$ARGS -my_flag VAL`), so the rule wins if a new flag slips
    past `forbidden`.

    Args:
        label (Label): `ctx.label`, for the error message.
        attr_name (str): the attr the args came from.
        args (list[str]): the user-supplied args.
        forbidden (list[str]): flag strings the rule manages.
    """
    for arg in args:
        if arg in forbidden:
            fail(("{label}: `{attr} = [...]` cannot contain `{arg}` — that " +
                  "flag is rule-controlled (the rule emits it from a " +
                  "dedicated attribute / from its declared outputs). Remove " +
                  "`{arg}` from `{attr}`; if you need a different value, " +
                  "either set the corresponding rule attr or open a " +
                  "rules_vivado issue.").format(
                label = label,
                attr = attr_name,
                arg = arg,
            ))

# ============================================================================
# Toolchain resolution
# ============================================================================

def get_vivado_toolchain(ctx):
    """Resolve the Vivado toolchain settings for an action."""
    return ctx.toolchains[TOOLCHAIN_TYPE].vivado_info

# ============================================================================
# Hooks
# ============================================================================
#
# A hook attr accepts a plain file (`.tcl`/`.xdc`/`.sdc`) that Vivado sources
# directly, or a `tcl_binary`. Under the attr's `hook_transition` a
# `tcl_binary` resolves against the Vivado tcl toolchain and emits a
# `.vhook.tcl` wrapper that self-locates its runfiles and sources `main`;
# that extension is in the allowlist below because the transitioned binary's
# `DefaultInfo.files` carries only the wrapper, never the stock `.sh` one.
DEFAULT_HOOK_EXTS = [".tcl", ".xdc", ".sdc", ".vhook.tcl"]

# Shared Tcl procs (`::rules_vivado::timing_gate`, `::rules_vivado::run_reports`,
# …) that phase templates `source` instead of each carrying its own copy.
# Reaches the templates through `run_tcl_template`'s `{{RULES_VIVADO_TCL}}`
# substitution; `action_attrs` is what puts the file on a rule.
_RULES_VIVADO_TCL_ATTR = "_rules_vivado_tcl"

_PROJECT_HOOKS_DOC = (
    "`.tcl`/`.xdc`/`.sdc` files OR `tcl_binary` targets sourced INSIDE " +
    "any downstream `vivado_project` action that folds this target in " +
    "via `ip_blocks` / `block_designs`. Fires right after `create_project` " +
    "+ `source_mgmt_mode`, before any `add_files`. Home for setup the " +
    "target needs to work in context (`board_part`, `set_msg_config`, TCL " +
    "procs). Does NOT run in this target's own action — for that use " +
    "`pre_hooks` / `post_hooks`. Sourced in list order; multiple targets' " +
    "contributions concat in project-attr dep order; the project's own " +
    "`pre_hooks_early` fires last so it wins on override."
)

def tcl_hook_flag_attrs():
    """Return the private attr every rule that calls `hook_invocation` needs.

    Carries `//vivado/settings:incompatible_eager_tcl_hook_load` into the
    rule so `hook_invocation` can read it off `ctx`. Rules that take
    `hook_attrs` get it for free; rules declaring hook attrs by hand
    (`vivado_project`) merge this in themselves.

    Returns:
        dict[str, Attribute]: the `_eager_tcl_hook_load` attr.
    """
    return {
        # EAGER-TCL-HOOK-LOAD: delete with the flag.
        "_eager_tcl_hook_load": attr.label(
            default = Label("//vivado/settings:incompatible_eager_tcl_hook_load"),
            providers = [BuildSettingInfo],
        ),
    }

def action_attrs():
    """Return the private attrs every rule that runs `run_tcl_template` needs.

    Returns:
        dict[str, Attribute]: the shared-Tcl-library attr whose file
        `run_tcl_template` stages and exposes as `{{RULES_VIVADO_TCL}}`.
    """
    return {
        _RULES_VIVADO_TCL_ATTR: attr.label(
            default = Label("//vivado/private:rules_vivado.tcl"),
            allow_single_file = [".tcl"],
        ),
    }

def hook_attrs(*, pre_doc, post_doc, extensions = None):
    """Return the standard `pre_hooks` / `post_hooks` / allowlist attrs.

    Rules merge the result into their own `attrs` dict so every
    hook-having rule shares one attr shape. Every hook-having rule also
    runs Vivado, so the result folds in `action_attrs` and
    `tcl_hook_flag_attrs`.

    Args:
        pre_doc (str): doc string body for the `pre_hooks` attr.
        post_doc (str): doc string body for the `post_hooks` attr.
        extensions (list[str]): allowed file extensions. Defaults to
            `.tcl`/`.xdc`/`.sdc`; simulation rules pass `[".tcl"]` when
            constraints don't apply.

    Returns:
        dict[str, Attribute]: the `pre_hooks` / `post_hooks` attrs plus
        the private attrs they depend on.
    """
    if extensions == None:
        extensions = DEFAULT_HOOK_EXTS
    return {
        "post_hooks": attr.label_list(
            doc = post_doc,
            allow_files = extensions,
            cfg = hook_transition,
            default = [],
        ),
        "pre_hooks": attr.label_list(
            doc = pre_doc,
            allow_files = extensions,
            cfg = hook_transition,
            default = [],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    } | action_attrs() | tcl_hook_flag_attrs()

def project_hooks_attr(doc = None):
    """Return the `project_hooks` attr shared by IP / BD producing rules.

    Args:
        doc (str, optional): rule-specific doc string; defaults to the
            generic wording.

    Returns:
        Attribute: an `attr.label_list` for a rule's
        `attrs = {"project_hooks": ...}`. Rules using it must also
        declare `_allowlist_function_transition` (included via
        `hook_attrs`).
    """
    return attr.label_list(
        doc = doc if doc != None else _PROJECT_HOOKS_DOC,
        allow_files = DEFAULT_HOOK_EXTS,
        cfg = hook_transition,
        default = [],
    )

def tcl_script_attr(doc = None):
    """Return the standard `script` attr for rules driven by a Tcl script.

    Requires an executable target — in practice a `tcl_binary`. A bare
    `.tcl` file is deliberately not accepted: it has no `deps`, so it can
    never `package require` a `tcl_library`, and nothing puts one on its
    `auto_path`. Only an executable carries the runfiles tree and the
    `.vhook.tcl` wrapper that make dependency-bearing Tcl work at all, so
    requiring one here is what makes `script` dep-capable by construction
    rather than by flag. Wrapping a self-contained script is three lines
    and costs nothing.

    `cfg = hook_transition` prepends the Vivado tcl toolchain to
    `--extra_toolchains` for the subgraph rooted at `script`, so the
    `tcl_binary` resolves against the Vivado-flavored toolchain rather
    than whatever the consumer registered, and its wrapper comes out as a
    `.vhook.tcl` Vivado can source. Rules using this attr must also pull
    in `_allowlist_function_transition` (already included via
    `hook_attrs`).

    Args:
        doc (str, optional): override the attr doc string. Defaults to
            the generic wording; pass a rule-specific one where the
            script has a contract to describe.

    Returns:
        Attribute: an `attr.label` for a rule's `attrs = {"script": ...}`.
    """
    if doc == None:
        doc = ("Tcl script sourced inside Vivado. Must be an executable " +
               "target — a `tcl_binary`, whose `.vhook.tcl` wrapper is " +
               "sourced and whose `tcl_library` deps are staged into the " +
               "sandbox as runfiles and reached with `package require`. " +
               "A bare `.tcl` file is not accepted; wrap it in a " +
               "`tcl_binary(name = ..., srcs = [\"script.tcl\"])`.")
    return attr.label(
        doc = doc,
        mandatory = True,
        cfg = hook_transition,
    )

def tcl_script_data(target):
    """Resolve a `tcl_script_attr`-shaped attribute to path + tools.

    The target contributes its wrapper exe and a `FilesToRunProvider`,
    which is what stages the runfiles tree next to it — that's how the
    `.vhook.tcl` wrapper self-locates its `tcl_library` closure and sets
    `auto_path`. `cfg = hook_transition` makes the attr a 1-element list
    at the callsite, so pass `ctx.attr.script[0]`.

    Args:
        target (Target): the single Target from a `tcl_script_attr` attr.

    Returns:
        struct: `path` (str) and `tools` (list[File|FilesToRunProvider],
        as `run_shell(tools=…)` accepts).
    """
    info = target[DefaultInfo]
    if not info.files_to_run or not info.files_to_run.executable:
        fail(("tcl_script: target {} is not executable. Wrap the script in a " +
              "`tcl_binary` so its `tcl_library` deps reach Vivado's " +
              "`auto_path`:\n\n" +
              "    load(\"@rules_tcl//tcl:defs.bzl\", \"tcl_binary\")\n\n" +
              "    tcl_binary(\n" +
              "        name = \"{}_tcl\",\n" +
              "        srcs = [\"<script>.tcl\"],\n" +
              "        deps = [],  # tcl_library targets the script `package require`s\n" +
              "    )").format(target.label, target.label.name.replace(".", "_")))
    return struct(
        path = info.files_to_run.executable.path,
        tools = [info.files_to_run],
    )

# EAGER-TCL-HOOK-LOAD: delete with the flag.
def _eager_tcl_srcs(target):
    """Transitive `tcl_library` srcs of a hook target, dependency-first.

    `TclInfo.transitive_srcs` is a postorder depset, so flattening it
    already yields the topological order a file-DAG build would compute:
    a library's own srcs come after everything it depends on. Targets
    with no `TclInfo` (raw files, filegroups) contribute nothing.

    Only first-party sources are eligible. A file from an external repo
    (`@rules_tcl//tcl/runfiles`, `@rules_vivado//vivado/hooks`, …) is a
    real Tcl package: it ships a `pkgIndex.tcl` and expects to be pulled
    in by `package require`, which registers it once and binds `$dir` for
    `rlocation`. Sourcing such a file directly bypasses that and either
    redefines a package Tcl already loaded or leaves `$dir` unset. The
    flag exists for un-packaged workspace Tcl, so it stops at the
    repository boundary.
    """
    if TclInfo not in target:
        return []
    return [
        f
        for f in target[TclInfo].transitive_srcs.to_list()
        if f.basename != "pkgIndex.tcl" and not f.owner.workspace_name
    ]

def hook_invocation(ctx, targets, script = None):
    """Resolve hook targets into sourceable paths and tools to stage.

    An executable target contributes its wrapper exe, staged via
    `FilesToRunProvider` so Bazel renders the runfiles tree next to it —
    that's how a `tcl_binary` wrapper self-locates its dep tree. Anything
    else (raw `.tcl`/`.xdc`/`.sdc`, `filegroup`, `tcl_library`)
    contributes each of its files, in order, staged individually; no
    runfiles tree exists for those, so they only get the files they list.

    `pkgIndex.tcl` stages but is never sourced — it binds `$dir` and
    errors when sourced directly. Skipping it lets one `tcl_library`
    serve both hook consumers (sourced file-by-file) and
    `package require` consumers (loaded via `auto_path`).

    Under `//vivado/settings:incompatible_eager_tcl_hook_load`, each
    target's transitive `tcl_library` srcs are sourced first, in
    dependency order, so a hook resolves procs it never declared a
    `package require` for.

    Each file is sourced at most once, keeping its earliest position.
    Listing a library both as its own hook and as another hook's dep is
    ordinary Bazel composition, but Tcl has no include guard — sourcing
    twice re-runs the file, so a `namespace eval` that appends to a list
    or bumps a counter would do it again. Dependency order is preserved
    because the first occurrence is the one deep enough for every later
    consumer.

    `script` is the rule's Tcl script, which every template sources right
    after this list. Under the flag its `tcl_library` closure is appended
    last, so the script resolves procs from libraries it declared in
    `deps` — the same reach a hook gets. Without it the two attrs
    disagree: a library named in `pre_hooks` is sourced, while the same
    library in the script's own `deps` is only staged into runfiles, and
    the script dies on `invalid command name`. `script` itself is not
    added here; the template sources it.

    Args:
        ctx (ctx): the rule context; the rule must carry
            `tcl_hook_flag_attrs()` (`hook_attrs` includes it).
        targets (list[Target]): Targets from a hook `label_list`.
        script (Target, optional): the `tcl_script_attr` target sourced
            after these hooks. Only its dependency closure is contributed.

    Returns:
        struct: `files_literal` (str) — a Tcl list literal of exec-root
        paths Vivado `source`s in order — and `tools`
        (list[File|FilesToRunProvider]) for `run_shell(tools=…)`.
    """

    # EAGER-TCL-HOOK-LOAD: delete with the flag.
    eager = ctx.attr._eager_tcl_hook_load[BuildSettingInfo].value
    paths = []
    seen = {}
    tools = []

    def add_path(path):
        if path in seen:
            return
        seen[path] = None
        paths.append(path)

    for t in targets:
        # EAGER-TCL-HOOK-LOAD: delete this branch with the flag. The
        # dedup above is independent and stays — two hooks legitimately
        # sharing a file is not specific to eager loading.
        if eager:
            for f in _eager_tcl_srcs(t):
                add_path(f.path)
                tools.append(f)
        info = t[DefaultInfo]
        if info.files_to_run and info.files_to_run.executable:
            add_path(info.files_to_run.executable.path)
            tools.append(info.files_to_run)
        else:
            for f in t.files.to_list():
                if f.basename != "pkgIndex.tcl":
                    add_path(f.path)
                tools.append(f)

    # EAGER-TCL-HOOK-LOAD: delete with the flag.
    if eager and script != None:
        for f in _eager_tcl_srcs(script):
            add_path(f.path)
            tools.append(f)

    return struct(
        files_literal = _tcl_list(paths),
        tools = tools,
    )

def merge_project_hook_contributions(*, ctx, block_designs, ip_blocks):
    """Union the `project_hooks` Targets that BD / IP providers contribute.

    Merged in dep order (BDs first, then IPs, each in list order) and run
    through `hook_invocation` like any other hook attr. Duplicates are
    dropped keeping the FIRST occurrence — a setup hook contributed by two
    BDs is normal composition, and sourcing it twice would re-run whatever
    it does (`create_bd_cell`, `set_property`, counter bumps).

    Args:
        ctx (ctx): the rule context (see `hook_invocation`).
        block_designs (list[Target]): providers of `VivadoBlockDesignInfo`.
        ip_blocks (list[Target]): providers of `VivadoIPBlockInfo`.

    Returns:
        struct: same shape as `hook_invocation`.
    """
    contributions = []
    for bd in block_designs:
        contributions.extend(bd[VivadoBlockDesignInfo].project_hooks)
    for ip in ip_blocks:
        contributions.extend(ip[VivadoIPBlockInfo].project_hooks)

    hook_targets = []
    seen = {}
    for target in contributions:
        key = str(target.label)
        if key in seen:
            continue
        seen[key] = True
        hook_targets.append(target)
    return hook_invocation(ctx, hook_targets)

def exec_hooks_data(targets, *, project_dir_path, export_dir_path):
    """Build subprocess invocations for executable hooks.

    Hooks run in listed order under `set -e`; the first non-zero exit fails
    the action.

    Args:
        targets (list[Target]): Targets from an executable-only hook
            `label_list`.
        project_dir_path (str): path of the rule's project TreeArtifact.
        export_dir_path (str): path of the rule's export TreeArtifact.

    Returns:
        struct: `command` (str), `env` (dict[str, str]), and `tools`
        (list[FilesToRunProvider]) — pass `tools` to
        `run_shell(tools=…)` so hook runfiles stage in the sandbox.
    """
    snippets = []
    tools = []
    for t in targets:
        exec_file = t[DefaultInfo].files_to_run.executable
        if exec_file == None:
            fail(("hook target {} is not executable — pass a rule that " +
                  "produces an executable (`sh_binary`, `py_binary`, " +
                  "`cc_binary`, `*_test`, or a rule setting " +
                  "`DefaultInfo(executable=...)`). Plain source files " +
                  "and `filegroup`s are rejected because the action " +
                  "invokes each hook as a subprocess.").format(t.label))
        snippets.append(
            "\"" + exec_file.path + "\"" +
            " --project-dir \"" + project_dir_path + "\"" +
            " --export-dir \"" + export_dir_path + "\"",
        )
        tools.append(t[DefaultInfo].files_to_run)
    env = {}
    if tools:
        env["VIVADO_PROJECT_DIR"] = project_dir_path
        env["VIVADO_EXPORT_DIR"] = export_dir_path
    return struct(
        command = "\n".join(snippets),
        tools = tools,
        env = env,
    )

# ============================================================================
# Report registry
# ============================================================================
#
# Splitting `filename` from `cmd` lets variants of one Vivado command land at
# distinct paths (e.g. `power` -> `power.rpt`, `power_xpe` -> `power.xpe`).
# Keep sorted alphabetically.

def _report(*, cmd, filename):
    """Build a REPORT_TYPES entry.

    Args:
        cmd (str): Tcl command template; `{OUT}` marks the output path.
        filename (str): canonical filename Vivado writes to.

    Returns:
        struct: `cmd` (str) and `filename` (str).
    """
    return struct(cmd = cmd, filename = filename)

REPORT_TYPES = {
    "cdc": _report(cmd = "report_cdc -file {OUT}", filename = "cdc.rpt"),
    "clock_interaction": _report(cmd = "report_clock_interaction -file {OUT}", filename = "clock_interaction.rpt"),
    "clock_networks": _report(cmd = "report_clock_networks -file {OUT}", filename = "clock_networks.rpt"),
    "clock_utilization": _report(cmd = "report_clock_utilization -file {OUT}", filename = "clock_utilization.rpt"),
    "clocks": _report(cmd = "report_clocks -file {OUT}", filename = "clocks.rpt"),
    "compile_order": _report(cmd = "report_compile_order -file {OUT}", filename = "compile_order.rpt"),
    "drc": _report(cmd = "report_drc -file {OUT}", filename = "drc.rpt"),
    "io": _report(cmd = "report_io -file {OUT}", filename = "io.rpt"),
    "methodology": _report(cmd = "report_methodology -file {OUT}", filename = "methodology.rpt"),
    "power": _report(cmd = "report_power -file {OUT}", filename = "power.rpt"),
    "power_xpe": _report(cmd = "report_power -xpe {OUT}", filename = "power.xpe"),
    "pulse_width": _report(cmd = "report_pulse_width -file {OUT}", filename = "pulse_width.rpt"),
    "qor_assessment": _report(cmd = "report_qor_assessment -file {OUT}", filename = "qor_assessment.rpt"),
    "qor_suggestions": _report(cmd = "report_qor_suggestions -file {OUT}", filename = "qor_suggestions.rpt"),
    "ram_utilization": _report(cmd = "report_ram_utilization -file {OUT}", filename = "ram_utilization.rpt"),
    "route_status": _report(cmd = "report_route_status -file {OUT}", filename = "route_status.rpt"),
    "timing_summary": _report(cmd = "report_timing_summary -file {OUT}", filename = "timing_summary.rpt"),
    "utilization": _report(cmd = "report_utilization -file {OUT}", filename = "utilization.rpt"),
}

# All-types dict rendered once at load time. Every report action embeds the
# same table so the tcl `switch` inside the template can look up any type;
# per-action work only picks the *requested* subset from `REQUESTED_REPORTS`.
_REPORT_COMMANDS_TCL_DICT = _tcl_dict([
    (t, REPORT_TYPES[t].cmd)
    for t in sorted(REPORT_TYPES.keys())
])

def reports_data(ctx, reports):
    """Render the `reports` attr into substitution data.

    Args:
        ctx (ctx): the rule context.
        reports (list[str]): report types; each must key `REPORT_TYPES`.

    Returns:
        struct: `commands_dict` (str), `requested` (str), `files`
        (list[File]), and `file_dict` (dict[str, File]).
    """
    if not reports:
        return struct(
            commands_dict = _tcl_dict([]),
            requested = _tcl_tuples([]),
            files = [],
            file_dict = {},
        )

    unknown = sorted([t for t in reports if t not in REPORT_TYPES])
    if unknown:
        fail("Unknown report types {}. Valid types: {}".format(
            unknown,
            sorted(REPORT_TYPES.keys()),
        ))

    # Per-target subdirectory so two phase targets in the same package can
    # request identical report types without colliding on declared paths.
    subdir = "{}.reports".format(ctx.label.name)
    files = []
    file_dict = {}
    rows = []
    for report_type in sorted(reports):
        entry = REPORT_TYPES[report_type]
        out_file = ctx.actions.declare_file("{}/{}".format(subdir, entry.filename))
        files.append(out_file)
        file_dict[report_type] = out_file
        rows.append([report_type, out_file.path])

    return struct(
        commands_dict = _REPORT_COMMANDS_TCL_DICT,
        requested = _tcl_tuples(rows),
        files = files,
        file_dict = file_dict,
    )

# ============================================================================
# run_tcl_template
# ============================================================================

# What the sanitizer substitutes for the sandbox-root prefix. Single source
# of truth for the template's argv literal and for consumers that grep
# sanitized outputs.
EXECROOT_MARKER = "<execroot>/"

# `export USER="${BUILD_USER:-}"` — Vivado's `create_waiver` and other
# metadata-writing commands invoked from IP-provided XDCs read `$USER` and
# raise CRITICAL WARNING [Vivado_Tcl 4-907] when it's empty (the norm on
# sandboxed RBE workers). `$BUILD_USER` comes from the toolchain env
# (aligned with Bazel `--stamp`'s workspace-status field).
#
# The trap re-emits the Vivado log to stderr on failure — Vivado's stdout is
# discarded because `-log` is the authoritative capture — then sanitizes the
# declared outputs. Sanitizer failures are swallowed: they must never turn a
# successful Vivado run into a build failure.
_VIVADO_COMMAND = """\
set -e
export USER="${BUILD_USER:-}"
_SANDBOX_ROOT="$(pwd)"
{{PRE_HOOKS}}
{{XILINX_ENV_SOURCE}}
trap 'rc=$?; if [ "$rc" -ne 0 ]; then echo "ERROR: vivado exited with status $rc. Log follows ({{LOG}}):" >&2; cat "{{LOG}}" >&2 2>/dev/null || true; fi; {{SANITIZE_COMMAND}}' EXIT INT TERM
"{{VIVADO_EXE}}" -mode batch -source "{{TCL}}" -log "{{LOG}}" -journal "{{JOURNAL}}" > /dev/null
{{POST_HOOKS}}
"""

# A toolchain built by a third-party rule may carry no `sanitizer`; the
# outputs then keep their sandbox paths (less cacheable, still correct).
_SANITIZE_COMMAND = '"{{SANITIZE_EXE}}" "$_SANDBOX_ROOT" "{{EXECROOT_MARKER}}" {{SANITIZE_OUTPUTS}} 2>/dev/null || true'

def run_tcl_template(
        *,
        ctx,
        toolchain,
        template,
        substitutions,
        input_files,
        output_files,
        mnemonic,
        jobs = 1,
        pre_processing_command = "",
        post_processing_command = "",
        tools = [],
        hook_env = {},
        extra_execution_requirements = {},
        progress_message = None):
    """Render a Tcl template and run it under `vivado -mode batch`.

    Args:
        ctx (ctx): the rule context.
        toolchain (VivadoToolchainInfo): from `get_vivado_toolchain`.
        template (File): the template file to render.
        substitutions (dict[str, str]): applied to `template`.
        input_files (list[File]): inputs Vivado needs.
        output_files (list[File]): expected outputs of the Tcl script. The
            log and journal are appended, and every entry is sanitized.
        mnemonic (str): short CamelCase identifier shown in Bazel output.
        jobs (int): how many CPUs Vivado will use; a scheduler
            `resource_set` hint, clamped at `MAX_VIVADO_THREADS`.
        pre_processing_command (str): bash run BEFORE vivado.
        post_processing_command (str): bash run AFTER vivado.
        tools (list): Files / `FilesToRunProvider`s to stage alongside
            the action (with runfiles when present) — hook closures from
            `exec_hooks_data` / `hook_invocation` / `tcl_script_data`,
            plus any rule-private executable the command shells out to.
        hook_env (dict[str, str]): env vars merged into the action.
            Toolchain env wins on collision; hooks can only augment.
        extra_execution_requirements (dict[str, str]): merged into the
            action's `execution_requirements`.
        progress_message (str): optional progress message for the action.

    When the rule carries `action_attrs()`, the shared Tcl library is
    staged as an input and its path substituted for `{{RULES_VIVADO_TCL}}`
    so the template can `source` it.

    Returns:
        struct: `outputs` (list[File]), `log` (File), `journal` (File),
        and `vivado_tcl` (File) — the rendered per-phase script.
    """

    # Every Vivado-invoking rule funnels its `jobs` / `threads` attr through
    # here, so this is the one place that can name the offending target.
    # Without it a `threads = 0` surfaces as `key 0 not found in dictionary`
    # from the resource-set table, naming neither the attr nor the target.
    if jobs < 1:
        fail(("{}: `jobs` / `threads` must be >= 1 (got {}). A Vivado " +
              "process always occupies at least one CPU; use 1 for " +
              "single-threaded phases.").format(ctx.label, jobs))

    vivado_tcl = ctx.actions.declare_file("{}_run_vivado.tcl".format(ctx.label.name))
    vivado_log = ctx.actions.declare_file("{}.log".format(ctx.label.name))
    vivado_journal = ctx.actions.declare_file("{}.jou".format(ctx.label.name))

    action_inputs = input_files + [vivado_tcl]
    if toolchain.xilinx_env:
        action_inputs.append(toolchain.xilinx_env)

    rules_vivado_tcl = getattr(ctx.file, _RULES_VIVADO_TCL_ATTR, None)
    if rules_vivado_tcl != None:
        substitutions = dict(substitutions)
        substitutions["{{RULES_VIVADO_TCL}}"] = rules_vivado_tcl.path
        action_inputs.append(rules_vivado_tcl)

    ctx.actions.expand_template(
        template = template,
        output = vivado_tcl,
        substitutions = substitutions,
    )

    outputs = output_files + [vivado_log, vivado_journal]

    # Sanitize declared outputs (single files + TreeArtifact dirs). Log +
    # journal ride along so cached artifacts are host-agnostic.
    sanitize_targets = " ".join(["\"" + f.path + "\"" for f in outputs])

    sanitizer = toolchain.sanitizer
    sanitize_command = _SANITIZE_COMMAND if sanitizer else "true"

    # Substitute paths BEFORE hook snippets so a hook whose path or args
    # happen to contain a `{{…}}` sequence can't collide with a placeholder
    # that was still pending expansion.
    command_substitutions = [
        ("{{SANITIZE_COMMAND}}", sanitize_command),
        ("{{VIVADO_EXE}}", toolchain.vivado.executable.path),
        ("{{TCL}}", vivado_tcl.path),
        ("{{LOG}}", vivado_log.path),
        ("{{JOURNAL}}", vivado_journal.path),
        ("{{XILINX_ENV_SOURCE}}", "source \"" + toolchain.xilinx_env.path + "\"" if toolchain.xilinx_env else ""),
        ("{{SANITIZE_EXE}}", sanitizer.executable.path if sanitizer else ""),
        ("{{EXECROOT_MARKER}}", EXECROOT_MARKER),
        ("{{SANITIZE_OUTPUTS}}", sanitize_targets),
        ("{{PRE_HOOKS}}", pre_processing_command),
        ("{{POST_HOOKS}}", post_processing_command),
    ]
    vivado_command = _VIVADO_COMMAND
    for key, value in command_substitutions:
        vivado_command = vivado_command.replace(key, value)

    execution_requirements = dict(extra_execution_requirements)
    if toolchain.requires_network:
        execution_requirements["requires-network"] = ""
    for resource_name, resource_count in toolchain.resources.items():
        execution_requirements["resources:" + resource_name] = resource_count

    if progress_message == None:
        progress_message = "{} %{{label}}".format(mnemonic)

    # Toolchain env wins on key collision — hooks can only augment.
    action_env = dict(hook_env)
    for k, v in toolchain.env.items():
        action_env[k] = v

    ctx.actions.run_shell(
        outputs = outputs,
        inputs = action_inputs,
        tools = [toolchain.vivado] + ([sanitizer] if sanitizer else []) + tools,
        progress_message = progress_message,
        command = vivado_command,
        mnemonic = mnemonic,
        toolchain = TOOLCHAIN_TYPE,
        resource_set = get_resource_set(jobs),
        execution_requirements = execution_requirements,
        env = action_env,
    )

    return struct(
        outputs = outputs,
        log = vivado_log,
        journal = vivado_journal,
        # The rendered per-phase Tcl script. Phase rules surface it on the
        # `tcl` field of their provider, or — when they emit no provider to
        # carry it — as an `OutputGroupInfo` group named `tcl`. Either way
        # an aspect can walk the phase chain and collect every script.
        vivado_tcl = vivado_tcl,
    )

# ============================================================================
# HDL source data
# ============================================================================

_DEFAULT_VHDL_LIBRARY = "xil_defaultlib"
_DEFAULT_VHDL_STANDARD = "2008"

def _hdl_row(file, vhdl_library, vhdl_standard):
    """Return a (kind, path, library, standard) tuple; None to skip the file."""
    ext = file.extension
    if ext == "v":
        return ("verilog", file.path, "xil_defaultlib", "")
    if ext == "sv":
        return ("systemverilog", file.path, "xil_defaultlib", "")
    if ext in ["vhd", "vhdl"]:
        return ("vhdl", file.path, vhdl_library, vhdl_standard)
    if ext == "tcl":
        return ("tcl", file.path, "", "")
    if ext == "xdc":
        return ("xdc", file.path, "", "")
    if ext in ["xml", "json"]:
        return None
    return ("import", file.path, "", "")

def hdl_sources_data(module):
    """Walk a module's transitive sources and split into per-kind Tcl lists.

    Walks `VerilogInfo.vhdl_deps` and `VhdlInfo.verilog_deps` so cross-lang
    instantiations reach the synth project. Without this, synth fails with
    `[Synth 8-439] module '<entity>' not found`.

    `.vhd` files reached via `VerilogInfo.data` (no `VhdlInfo` context) fall
    back to (`xil_defaultlib`, `2008`).

    TreeArtifact directory Files (e.g. from `vivado_xci` categorized outputs)
    are collected into `src_dirs` and consumed by templates via `add_files`
    — Vivado auto-classifies files by extension inside the directory.

    Args:
        module (Target): the top-level HDL library target.

    Returns:
        struct: `all_files` (list[File]) plus the Tcl literals
        `hdl_sources`, `src_dirs`, `xdc_files`, and `tcl_files` (str).
    """
    all_files = []
    hdl_rows = []
    xdc_paths = []
    tcl_paths = []
    src_dir_paths = []
    seen_dirs = {}

    def _process(file, vhdl_library, vhdl_standard):
        all_files.append(file)
        if file.is_directory:
            if file.path not in seen_dirs:
                seen_dirs[file.path] = True
                src_dir_paths.append(file.path)
            return
        row = _hdl_row(file, vhdl_library, vhdl_standard)
        if row == None:
            return
        kind = row[0]
        if kind == "xdc":
            xdc_paths.append(row[1])
        elif kind == "tcl":
            tcl_paths.append(row[1])
        else:
            hdl_rows.append(list(row))

    def _process_verilog(v):
        for f in v.srcs.to_list() + v.hdrs.to_list() + v.data.to_list():
            _process(f, _DEFAULT_VHDL_LIBRARY, _DEFAULT_VHDL_STANDARD)

    def _process_vhdl(v):
        vhdl_library = v.library if v.library else _DEFAULT_VHDL_LIBRARY
        vhdl_standard = v.standard if v.standard else _DEFAULT_VHDL_STANDARD
        for f in v.srcs.to_list() + v.data.to_list():
            _process(f, vhdl_library, vhdl_standard)

    if VerilogInfo in module:
        info = module[VerilogInfo]
        for v in info.deps.to_list() + [info]:
            _process_verilog(v)
        for v in info.vhdl_deps.to_list():
            _process_vhdl(v)
    if VhdlInfo in module:
        info = module[VhdlInfo]
        for v in info.deps.to_list() + [info]:
            _process_vhdl(v)
        for v in info.verilog_deps.to_list():
            _process_verilog(v)

    return struct(
        all_files = all_files,
        hdl_sources = _tcl_tuples(hdl_rows),
        src_dirs = _tcl_list(src_dir_paths),
        xdc_files = _tcl_list(xdc_paths),
        tcl_files = _tcl_list(tcl_paths),
    )

# ============================================================================
# IP-block data
# ============================================================================

def ip_blocks_data(ip_blocks):
    """Extract `ip_blocks` deps into substitution-ready Tcl literals.

    Args:
        ip_blocks (list[Target]): providers of `VivadoIPBlockInfo`.

    Returns:
        struct: the Tcl literals `ip_repos`, `ip_configured_instances`,
        and `ip_instances` (str), plus `ip_repo_paths` (list[str]) and
        `input_files` (list[File]).
    """
    repo_paths = []
    repo_files = []
    configured_rows = []
    instance_rows = []

    for ip_block in ip_blocks:
        info = ip_block[VivadoIPBlockInfo]
        for repo in info.repo:
            repo_paths.append(repo.path)
            repo_files.append(repo)
        if info.configured_instance:
            ci = info.configured_instance
            configured_rows.append([ci.module_top, ci.repo_dir.path, ci.xci_relpath])
        if info.instantiable:
            i = info.instantiable
            instance_rows.append([i.name, i.vendor, i.library, i.version, i.module_name])

    return struct(
        ip_repos = _tcl_list(repo_paths),
        ip_repo_paths = repo_paths,
        ip_configured_instances = _tcl_tuples(configured_rows),
        ip_instances = _tcl_tuples(instance_rows),
        input_files = repo_files,
    )

# ============================================================================
# Block-design data
# ============================================================================

def block_designs_data(block_designs):
    """Extract `block_designs` deps into a substitution-ready Tcl literal.

    Args:
        block_designs (list[Target]): providers of `VivadoBlockDesignInfo`.

    Returns:
        struct: `block_designs` (str, a Tcl literal); `input_files`
        (list[File]) — each BD's `bd_dir` plus its transitively
        referenced IP-block repo dirs; and `ip_repo_paths` (list[str]) —
        just those repo paths, which consumers must fold into their own
        `ip_repo_paths` for `create_bd_cell -vlnv` inside the BD to
        resolve when the BD is reloaded downstream.
    """
    rows = []
    input_files = []
    ip_repo_paths = []
    for bd in block_designs:
        info = bd[VivadoBlockDesignInfo]
        input_files.append(info.bd_dir)
        input_files.extend(info.ip_block_repos)
        for repo in info.ip_block_repos:
            ip_repo_paths.append(repo.path)
        rows.append([info.module_top, info.bd_dir.path])
    return struct(
        block_designs = _tcl_tuples(rows),
        ip_repo_paths = ip_repo_paths,
        input_files = input_files,
    )

# ============================================================================
# Encrypt data
# ============================================================================

def encrypt_data(*, ctx, all_files, ip_dir_src):
    """Produce substitution data + post-processing command for IP encryption.

    Args:
        ctx (ctx): the rule context.
        all_files (list[File]): every file the IP depends on; filtered to
            `.v` / `.sv` / `.vhd` here.
        ip_dir_src (str): path of the IP repo's `src/` directory.

    Returns:
        struct: `encrypt_files` (str, a Tcl literal),
        `encrypted_outputs` (list[File]), and
        `post_processing_command` (str).
    """
    rows = []
    encrypted_outputs = []
    post_processing_command = ""
    for file in all_files:
        if file.extension in ["v", "sv"]:
            language = "verilog"
        elif file.extension in ["vhd", "vhdl"]:
            language = "vhdl"
        else:
            continue
        enc_extension = ".enc.{}".format(file.extension)

        # `encrypt -ext <ext> <path>` writes `[file rootname <path>]<ext>`,
        # and Tcl's `rootname` strips only the LAST extension. Splitting on
        # the first `.` instead would declare `axi_lite.enc.sv` for an input
        # named `axi_lite.v2.sv` while Vivado writes `axi_lite.v2.enc.sv`,
        # and the copy below would fail on a missing source.
        stem = file.basename[:-(len(file.extension) + 1)]

        rows.append([language, enc_extension, file.path])

        # Mirror the input's directory under a per-target subdir: two
        # same-named sources in different packages (`a/util.sv` and
        # `b/util.sv`) both encrypt to `util.enc.sv`, which collides on a
        # flat declared path. Strip the output root so a generated input
        # nests under `tests/foo/` rather than
        # `bazel-out/k8-fastbuild/bin/tests/foo/`.
        rel_dir = file.dirname
        root = file.root.path
        if root and rel_dir.startswith(root + "/"):
            rel_dir = rel_dir[len(root) + 1:]
        enc_file = ctx.actions.declare_file("/".join([
            p
            for p in ["{}.encrypted".format(ctx.label.name), rel_dir, stem + enc_extension]
            if p
        ]))
        encrypted_outputs.append(enc_file)

        # Vivado writes the encrypted file next to its source, so the copy
        # source is the ORIGINAL directory plus the encrypted basename.
        source_file = "{}/{}".format(file.dirname, enc_file.basename)
        post_processing_command += "cp {} {}; ".format(source_file, enc_file.path)
        post_processing_command += "cp {} {}/{}; ".format(source_file, ip_dir_src, file.basename)

    return struct(
        encrypt_files = _tcl_tuples(rows),
        encrypted_outputs = encrypted_outputs,
        post_processing_command = post_processing_command,
    )
