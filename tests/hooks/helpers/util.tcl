package provide vivado_hook_helpers 1.0

namespace eval ::vivado_hook_helpers {
    proc announce {tag} {
        puts "HOOK(bin-tcl helper): announce=$tag"
    }
}
