#!/usr/bin/env bash
# Regression test for the Vivado hook wrapper generated from a
# `tcl_binary` when reached under `hook_transition`. Runs in normal
# `bazel test //...` — no Vivado required.
#
# What this pins:
#   1. The transition landed the tcl_binary on our `.tcl` wrapper
#      extension (via the `//vivado:vivado_tcl_toolchain` toolchain that
#      `hook_transition` prepends to `--extra_toolchains`), not the stock
#      `.sh` from `@rules_tcl//tcl/toolchain`.
#   2. The wrapper substitutes `{main}` to a `source` line pointing at the
#      user's entry `.tcl`.
#   3. The wrapper substitutes `{auto_path}` to a `lappend auto_path` loop
#      covering each transitive `tcl_library` `pkgIndex.tcl` directory.
#   4. Vivado-runtime self-location scaffolding survives — `[info script]`,
#      the manifest-vs-tree fallback, and the `_rv_rloc` resolver.

set -euo pipefail

wrapper="${WRAPPER_PATH:?WRAPPER_PATH env var must be set}"

if [[ ! -f "${wrapper}" ]]; then
    echo "regression: wrapper not staged at ${wrapper}" >&2
    exit 1
fi

# The transition must produce a `.vhook.tcl` — anything else means the
# stock `.sh` / `.bat` toolchain won and our `--extra_toolchains` prepend
# didn't take effect. `.vhook.tcl` (not `.tcl`) so the wrapper output
# can't collide with a user src file of the same base name in the
# runfiles tree, while the `.tcl` suffix keeps editor/lint recognition.
case "${wrapper}" in
    *.vhook.tcl) : ;;
    *) echo "regression: wrapper extension not .vhook.tcl: ${wrapper}" >&2; exit 1 ;;
esac

grep_or_fail() {
    local pattern="$1"
    local label="$2"
    if ! grep -qF -- "${pattern}" "${wrapper}"; then
        echo "regression: missing ${label} — pattern '${pattern}' not found in ${wrapper}" >&2
        echo "----- wrapper contents -----" >&2
        cat "${wrapper}" >&2
        exit 1
    fi
}

grep_or_fail "info script" "self-location scaffolding"
grep_or_fail "_rv_rloc_map" "rlocation resolver table"
grep_or_fail ".runfiles_manifest" "manifest fallback branch"
grep_or_fail "lappend auto_path" "auto_path expansion"
grep_or_fail "_main/tests/hooks/helpers" "tcl_library include (auto_path entry)"
grep_or_fail "source [_rv_rloc _main/tests/hooks/entry_hook.tcl]" "main source line"

# Isolation: the wrapper must snapshot `auto_path` before pushing this
# hook's tcl_library dirs onto it, then restore before returning, so a
# subsequent hook sourced in the same Vivado tclsh doesn't inherit this
# hook's dep dirs.
grep_or_fail "set _rv_saved_auto_path \$auto_path" "auto_path snapshot before lappend"
grep_or_fail "set auto_path \$_rv_saved_auto_path" "auto_path restore after source"

echo "hook wrapper regression: OK"
