# Body for the `vivado_project_export` instance. Runs against the
# already-sourced project; writes each path in $OUTS / $OUT_DIRS.
set fh [open [lindex $OUTS 0] w]
puts $fh [get_property PART [current_project]]
close $fh

file mkdir [lindex $OUT_DIRS 0]
