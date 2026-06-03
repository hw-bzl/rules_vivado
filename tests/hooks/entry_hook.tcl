package require vivado_hook_helpers 1.0

puts "HOOK(bin-tcl entry): sourced inside Vivado via tcl_binary wrapper"
::vivado_hook_helpers::announce "from-vivado"
