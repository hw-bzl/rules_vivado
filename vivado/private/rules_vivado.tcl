# Shared Tcl procs for rules_vivado phase templates.
#
# Staged into every Vivado action by `run_tcl_template` and sourced by the
# templates via `source {{RULES_VIVADO_TCL}}`, so logic that several phases
# share (post-route timing gate, report loop) lives in exactly one place.
# Everything is namespaced under `::rules_vivado` to stay clear of user
# hooks and Vivado's own commands.

namespace eval ::rules_vivado {}

# Worst slack for the given `get_timing_paths` flags (`-setup` / `-hold`).
#
# `get_property SLACK` errors when there are no post-route timing paths
# (no user clock constraints, or Versal-style all-PS routing). Probe the
# path list first so empty results roll into `""`, which `timing_gate`
# treats as "unconstrained" rather than as a pass.
proc ::rules_vivado::worst_slack {args} {
    set paths [get_timing_paths -max_paths 1 -nworst 1 {*}$args]
    if {[llength $paths] == 0} {
        return ""
    }
    return [get_property SLACK [lindex $paths 0]]
}

# Apply the rule's `timing_check` policy to the open routed design.
#
#   policy   ∈ {error, warn, none} — the rule's `timing_check` attr. Post-route
#            timing is a house-style policy call, not a Vivado one, so it is
#            an attr rather than something you fork a template to change.
#   artifact Human name of what is about to be written ("bitstream",
#            "device image"), used in the messages.
#
# Setup and hold are independent failures. A design can clear setup
# comfortably (WNS = +0.5) and still hold-violate (WHS = -0.150); a
# setup-only gate ships that board. Both are probed.
proc ::rules_vivado::timing_gate {policy artifact} {
    set wns [worst_slack -setup]
    set whs [worst_slack -hold]
    puts "Post Route WNS = $wns"
    puts "Post Route WHS = $whs"

    set violations {}
    if {$wns ne "" && $wns < 0} { lappend violations "setup (WNS = $wns)" }
    if {$whs ne "" && $whs < 0} { lappend violations "hold (WHS = $whs)" }

    if {[llength $violations] > 0} {
        set msg "Post-route timing not met: [join $violations {, }]."
        # `error` (not `puts`) so Bazel surfaces a timing fail as a real
        # action failure, not "expected output not created".
        switch -- $policy {
            error {
                error "$msg Refusing to write $artifact. Set `timing_check = \"warn\"` on the rule to downgrade this to a warning."
            }
            warn {
                puts "CRITICAL WARNING: $msg Writing $artifact anyway (timing_check = warn)."
            }
            none {}
            default {
                error "rules_vivado::timing_gate: unknown policy '$policy' (expected error, warn, or none)"
            }
        }
    } elseif {$wns eq "" && $whs eq ""} {
        puts "WARNING: No post-route timing paths found. Writing $artifact without timing validation."
    }
}

# Run the reports a phase rule requested.
#
#   commands  dict: report type -> Tcl command template with an `{OUT}`
#             placeholder (the rule's `REPORT_COMMANDS`).
#   requested list of {type out_path} tuples (the rule's `REQUESTED_REPORTS`).
#
# Each report is wrapped in `catch` so a single failure (e.g.
# `report_methodology` on an under-constrained design) doesn't abort the
# whole action. The error message is written to the report file itself so
# Bazel sees the declared output exist AND the user finds the diagnostic
# when opening the report.
proc ::rules_vivado::run_reports {commands requested} {
    foreach entry $requested {
        lassign $entry type out_file
        set cmd [string map [list "{OUT}" $out_file] [dict get $commands $type]]
        if {[catch [list uplevel #0 $cmd] err]} {
            puts stderr "WARNING: report '$type' failed: $err"
            set fh [open $out_file w]
            puts $fh "ERROR: report '$type' failed:\n$err"
            close $fh
        }
    }
}
