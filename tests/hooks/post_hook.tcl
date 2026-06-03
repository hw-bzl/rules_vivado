# TCL post-hook — sourced INSIDE Vivado at the end of the export
# body, AFTER `export_simulation` has populated the export tree but
# BEFORE `close_project`. The Vivado project is still open, so every
# `get_files` / `get_ips` query still resolves.
puts "HOOK(post-tcl): sourced inside Vivado at post-export point"
