# TCL pre-hook — sourced INSIDE Vivado at the top of the export
# body, BEFORE `export_simulation` runs. Setting globals or defining
# procs here changes what the rest of the template does. This demo
# just logs the fact that we ran; a real hook might set
# `xsim.simulate.log_all_signals` for waveform capture.
puts "HOOK(pre-tcl): sourced inside Vivado at pre-export point"
