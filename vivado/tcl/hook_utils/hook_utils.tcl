# Small utilities every rules_vivado hook script writer wants — assert
# a required env var is set and hand its value back as a plain string.
# `package require hook_utils` from your `tcl_binary` hook via
# `deps = ["@rules_vivado//vivado/tcl/hook_utils"]`.
#
# Why a package: rules_vivado's phase templates (write_device_image,
# synthesis, ...) publish per-action state as env vars — the standard
# hook-config channel because Vivado's `source` can't pass args. Every
# hook then wants the same env→assert→local-var dance at the top; this
# package factors it out so hooks stay short and the error message
# stays consistent.

package provide hook_utils 1.0

namespace eval hook_utils {
    namespace export require_env
}

# Return `$::env(<name>)` as a string, erroring with a clear message if
# the var is unset or empty. Prefer this over `[set ::env(<name>)]` at
# the top of a hook script so the failure mode is a legible one-line
# error, not a Tcl "can't read env(...)" traceback.
proc hook_utils::require_env {name} {
    if {![info exists ::env($name)] || [set ::env($name)] eq ""} {
        error "hook_utils::require_env: required env var '$name' is unset or empty"
    }
    return [set ::env($name)]
}
