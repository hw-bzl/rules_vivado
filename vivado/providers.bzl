"""# Vivado providers."""

VivadoProjectInfo = provider(
    doc = (
        "Output of `vivado_project`. Carries a self-contained TCL script " +
        "(produced by Starlark template expansion, no Vivado invocation) " +
        "that, when sourced inside a Vivado process, does `create_project` " +
        "+ source ingest + constraints + hooks (but NOT `generate_target` " +
        "— the consumer picks that intent). Downstream consumers " +
        "(`vivado_synthesis`, `vivado_export_simulation`, GUI launchers, " +
        "`vivado_project_export`) source this script in their own Vivado " +
        "action. The provider also carries the transitive input closure the " +
        "script references, plus typed access to the sub-providers folded " +
        "into the project, so consumers only need to depend on the " +
        "`vivado_project` target — never on its individual inputs."
    ),
    fields = {
        "block_designs": (
            "list[VivadoBlockDesignInfo]: typed access to the block-design " +
            "providers folded into the project via `block_designs = [...]`. " +
            "Enables downstream rules (e.g. `vivado_bd_wrapper`, project-" +
            "walking aspects) to reason about BDs by provider rather than " +
            "reparsing the project script or re-reading rule attrs."
        ),
        "hook_tools": (
            "list: File / FilesToRunProvider entries for `pre_hooks_early` " +
            "/ `pre_hooks` / `post_hooks` targets. Consumers pass this list " +
            "to `ctx.actions.run_shell(tools=...)` so hook runfiles trees " +
            "(needed by `tcl_binary`-based hooks) materialize in the sandbox."
        ),
        "input_files": (
            "depset[File]: transitive files the emitted script references " +
            "by exec-root path (HDL sources, IP repos, BD directories, " +
            "constraint files, hook files). Any consumer that SOURCES " +
            "`project_tcl` must pass `input_files.to_list()` as action " +
            "inputs, or the sandbox won't stage what the script tries to " +
            "open — `vivado_synthesis`, `vivado_project_export`, and the " +
            "`export_simulation` rules all do. Consumers that only read a " +
            "downstream checkpoint do NOT need it; see " +
            "`_CHECKPOINT_COMMON_FIELDS.input_files` below."
        ),
        "ip_blocks": (
            "list[VivadoIPBlockInfo]: typed access to the IP providers folded " +
            "into the project via `ip_blocks = [...]`. Symmetric with " +
            "`block_designs`."
        ),
        "module_top": "str: top-module name (matches `vivado_project.module_top`).",
        "part_number": "str: Xilinx part string (matches `vivado_project.part_number`).",
        "project_tcl": (
            "File: the emitted `.project.tcl` script. Sourcing this file " +
            "inside a Vivado process does `create_project` + " +
            "contributed `project_hooks` + `pre_hooks_early` + " +
            "`read_verilog` / `read_vhdl` / `add_files` + `read_xdc` + " +
            "`set_property top` + `pre_hooks`. It has no `post_hooks` and " +
            "runs no `generate_target` — the consumer issues that with the " +
            "intent it needs. Reads `PROJECT_MODE` / `PROJECT_DIR` from " +
            "pre-set Tcl variables or the `VIVADO_PROJECT_MODE` / " +
            "`VIVADO_PROJECT_DIR` env vars (default: `project` mode in `.`)."
        ),
        "xdc": (
            "depset[File]: transitive `.xdc` / `.sdc` / `.tcl` constraint " +
            "files contributed via `vivado_project.data`, in the exact " +
            "order the emitted script's `$PROJECT_DATA_FILES` loop reads " +
            "them: plain files at their listed position, `xdc_library` " +
            "targets expanded in place with their dep-first transitive " +
            "closure. Empty when the project has no `data` entries. " +
            "Enables aspects and future constraint-linting rules to walk " +
            "the constraint set without reparsing the emitted TCL."
        ),
    },
)

# ============================================================================
# Fields shared by every checkpoint provider (synth / place / route).
# Callers construct with these keys directly; documented here as the shared
# contract downstream rules can rely on.
# ============================================================================
_CHECKPOINT_COMMON_FIELDS = {
    "checkpoint": "File: the Vivado checkpoint (.dcp) this phase emitted.",
    "input_files": (
        "depset[File]: transitive files needed to re-open the checkpoint " +
        "with `read_checkpoint` + `link_design`. Includes the upstream " +
        "project's `input_files`, the upstream checkpoint file itself, and " +
        "any impl-XDC bundle.\n\n" +
        "Most consumers do NOT need this. A `.dcp` is self-contained, so " +
        "every in-tree phase rule that only `open_checkpoint`s " +
        "(`vivado_placement`, `vivado_place_optimize`, `vivado_routing`, " +
        "`vivado_synthesis_optimize`, `vivado_bitstream`, " +
        "`vivado_device_image`, `vivado_hw_platform`, " +
        "`vivado_debug_probes`) stages just the `.dcp` and keeps the " +
        "action's input set small. Pass `input_files.to_list()` only when " +
        "an action re-links the design against its original sources or " +
        "re-sources the project script."
    ),
    "module_top": (
        "str: top-module name (propagated from the originating " +
        "`vivado_project.module_top`). May be `\"\"` if the upstream " +
        "provider carried no top."
    ),
    "part_number": (
        "str: Xilinx part string (propagated from the originating " +
        "`vivado_project.part_number`). Consumers use this to open the " +
        "checkpoint on the correct part."
    ),
    "project_info": (
        "VivadoProjectInfo: typed back-reference to the originating project. " +
        "Enables consumers to trace a checkpoint back to design intent " +
        "(module tops, block designs, constraints) without needing a " +
        "separate `project = ...` attr on every downstream rule."
    ),
    "tcl": (
        "File: the fully-substituted TCL script the action sourced. " +
        "Useful for debugging (`bazel build //foo:x` produces this) and " +
        "for reproducing the phase outside Bazel (`vivado -source " +
        "<this-file>`)."
    ),
}

VivadoSynthCheckpointInfo = provider(
    doc = "Output of the synthesis phase (`vivado_synthesis` / `vivado_synthesis_optimize`).",
    fields = dict(_CHECKPOINT_COMMON_FIELDS, **{
        "impl_xdc": (
            "Optional[File]: Bundle of XDC content from source files marked " +
            "`USED_IN_IMPLEMENTATION == True`. `synth_design` doesn't apply " +
            "these and `write_checkpoint` only persists applied constraints, " +
            "so downstream phases must `read_xdc <bundle>` before " +
            "`opt_design` / `place_design` or the constraints are lost. " +
            "May be `None`; consumers must tolerate that case."
        ),
    }),
)

VivadoPlacementCheckpointInfo = provider(
    doc = "Output of the placement phase (`vivado_placement` / `vivado_place_optimize`).",
    fields = dict(_CHECKPOINT_COMMON_FIELDS),
)

VivadoRoutingCheckpointInfo = provider(
    doc = "Output of the routing phase (`vivado_routing`).",
    fields = dict(_CHECKPOINT_COMMON_FIELDS),
)

_PROJECT_HOOKS_DOC = (
    "list[Target]: hook Targets this target contributes as `project_hooks` " +
    "to any downstream `vivado_project` that lists it in `ip_blocks` / " +
    "`block_designs`. The consumer passes the merged Target list through " +
    "`hook_invocation` to derive both the sourceable paths (for the " +
    "emitted TCL) and the tools list (for `run_shell(tools = ...)` " +
    "staging). Sourced right after `create_project` + `source_mgmt_mode` " +
    "and before the project's own `pre_hooks_early`. Empty when the " +
    "target declares no `project_hooks`."
)

VivadoIPBlockInfo = provider(
    doc = "Describes the contents of a Vivado IP artifact. Consumers read the fields to decide whether to call `create_ip`, `add_files` a configured `.xci`, or just expose the repo on `ip_repo_paths`.",
    fields = {
        "configured_instance": (
            "Optional[struct(repo_dir: File, xci_relpath: str, module_top: str)]: " +
            "Set when the artifact contains a pre-configured IP instance. " +
            "Consumers add `<repo_dir>/<xci_relpath>` to their source set. " +
            "None when there is no configured instance."
        ),
        "instantiable": (
            "Optional[struct(vendor: str, library: str, name: str, " +
            "version: str, module_name: str)]: Set when consumers are " +
            "expected to `create_ip` with these VLNV identifiers and " +
            "`-module_name <module_name>`. None otherwise."
        ),
        "project_hooks": _PROJECT_HOOKS_DOC,
        "repo": "list[File]: Directory artifacts forming an IP repository (`component.xml`-rooted tree). Added to the consuming project's `ip_repo_paths`.",
    },
)

VivadoBlockDesignInfo = provider(
    doc = "Info for a Vivado block design (.bd) produced by `vivado_block_design`.",
    fields = {
        "bd_dir": "File: tree-artifact directory containing the generated `.bd` and its supporting files. The `.bd` itself is normalized to `<bd_dir>/<module_top>.bd` by the rule.",
        "ip_block_repos": "list[File]: IP repo directories from `ip_blocks` deps that must be added to the consuming project's `ip_repo_paths` for the BD to resolve.",
        "module_top": "string: The block-design name (the argument to `create_bd_design` in the source TCL). Consumers use `<bd_dir>/<module_top>.bd` to find the file.",
        "project_hooks": _PROJECT_HOOKS_DOC,
    },
)

VivadoLogInfo = provider(
    doc = "Aggregated Vivado `.log` and `.jou` files for a phase target and all its transitive upstream phases. Keys are short phase names (`synth`, `synth_opt`, `place`, `place_opt`, `route`, `write_bitstream`, `write_device_image`).",
    fields = {
        "journals": "dict[str, File]: phase name -> journal File.",
        "logs": "dict[str, File]: phase name -> log File.",
    },
)

VivadoReportsInfo = provider(
    doc = "Maps the `reports` attr's caller-chosen output names to the declared File objects.",
    fields = {
        "reports": "dict[str, File]: caller-chosen output filename -> declared File.",
    },
)

VivadoExportSimulationInfo = provider(
    doc = "Output of `vivado_export_simulation` — the directory Vivado writes when invoked with `export_simulation -directory <dir>`. Contents follow Vivado's contract for the chosen simulator (see UG835).",
    fields = {
        "export_dir": "File: TreeArtifact directory containing the export.",
        "project_info": (
            "VivadoProjectInfo: typed back-reference to the originating " +
            "project. Same purpose as on checkpoint providers."
        ),
        "simulator": "string: The `-simulator` argument passed to Vivado.",
        "tcl": (
            "File: the fully-substituted TCL script the action sourced. " +
            "See `VivadoSynthCheckpointInfo.tcl`."
        ),
    },
)

XdcInfo = provider(
    doc = (
        "Marker provider on `xdc_library` targets. Carries the " +
        "transitive closure of the `.xdc` / `.sdc` files a downstream " +
        "consumer should `read_xdc` in topological order (deps' srcs " +
        "before the target's own srcs). Independent of any HDL info — " +
        "`xdc_library` deliberately doesn't re-export VerilogInfo / " +
        "VhdlInfo. Exists as a first-class provider so aspects can " +
        "walk arbitrary dep graphs and pick out XDC-file contributors " +
        "by filtering for this marker."
    ),
    fields = {
        "srcs": (
            "depset[File]: transitive `.xdc`/`.sdc` files, deep-deps " +
            "first (topological order). The rule's `DefaultInfo.files` " +
            "is the same depset so this target also drops into " +
            "`vivado_project.data` — the flattened order Bazel derives " +
            "from `ctx.files.data` on a topological depset is what the " +
            "emitted TCL's `$PROJECT_DATA_FILES` loop iterates."
        ),
    },
)

VivadoCompiledSimlibInfo = provider(
    doc = "Output of `vivado_compile_simlib`. Layout matches `compile_simlib -directory <dir>`: `<simlib_dir>/<simulator>/` contains the simulator's link-config file plus per-library compiled artifacts.",
    fields = {
        "simlib_dir": "File: TreeArtifact directory containing the compiled simlib. The link-config file lives at `<simlib_dir>/<simulator>/<link_config_basename>` (e.g. `<simlib_dir>/riviera/library.cfg`).",
        "simulator": "string: The simulator the simlib targets. One of Vivado's `compile_simlib -simulator` choices.",
    },
)

VivadoInterfaceInfo = provider(
    doc = "Info for a Vivado IP-XACT interface definition",
    fields = {
        "abstraction_definition": "File: The abstraction definition XML file.",
        "bus_definition": "File: The bus definition XML file.",
        "library": "string: The library VLNV component.",
        "name": "string: The interface name.",
        "setup_tcl": "File: The TCL setup file for IP packaging.",
        "vendor": "string: The vendor VLNV component.",
        "version": "string: The version VLNV component.",
    },
)

VivadoHwPlatformInfo = provider(
    doc = (
        "Output of `vivado_hw_platform`. Wraps `write_hw_platform`; " +
        "produces the `.xsa` handoff artifact consumed by Vitis, " +
        "PetaLinux, and other Xilinx SDK tooling."
    ),
    fields = {
        "project_info": (
            "VivadoProjectInfo: typed back-reference to the originating " +
            "project (through the checkpoint chain)."
        ),
        "tcl": "File: the fully-substituted TCL script the action sourced.",
        "xsa": "File: the emitted `.xsa` hardware platform archive.",
    },
)

VivadoDebugProbesInfo = provider(
    doc = (
        "Output of `vivado_debug_probes`. Wraps `write_debug_probes`; " +
        "produces the `.ltx` probe file consumed by Vivado's Hardware " +
        "Manager during ILA bring-up."
    ),
    fields = {
        "ltx": "File: the emitted `.ltx` debug-probes file.",
        "project_info": (
            "VivadoProjectInfo: typed back-reference to the originating " +
            "project (through the checkpoint chain)."
        ),
        "tcl": "File: the fully-substituted TCL script the action sourced.",
    },
)
