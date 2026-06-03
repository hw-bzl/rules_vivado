# Second tcl_binary hook. Runs after `entry_hook` in the same
# PRE_HOOKS list and asserts that hook A's `tcl_library` dep dir
# (`tests/hooks/helpers/…`) is NOT still on `auto_path`. If the
# wrapper's save/restore is missing, that dir persists across the
# session and this assertion fires.
foreach _path $auto_path {
    if {[string match *tests/hooks/helpers* $_path]} {
        error "isolation broken: prior hook's tcl_library dir leaked onto auto_path: $_path"
    }
}
puts "HOOK(bin-tcl second): auto_path isolated from prior hook OK"
