package provide analysis_tcl_leaf 1.0

namespace eval ::analysis_tcl_leaf {
    proc tag {} {
        return "leaf-on-[::analysis_tcl_base::tag]"
    }
}
