# Fixture: a first-party hook whose `tcl_library` depends on a Tcl
# package shipped by an external repo. Only this file may be sourced
# eagerly — the dep's sources belong to `package require`.
namespace eval analysis_tcl_external {
    proc tag {} {
        return "analysis_tcl_external"
    }
}
