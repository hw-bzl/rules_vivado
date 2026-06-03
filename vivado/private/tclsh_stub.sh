#!/bin/sh
# Stub tclsh referenced by //vivado:vivado_tcl_toolchain_impl. Never
# invoked — Vivado is the interpreter at hook time. Fails loudly if
# something actually tries to run it.
echo "vivado_tcl_toolchain: the stub tclsh was invoked. This toolchain is only meant to produce hook wrappers Vivado sources itself; nothing should ever run this binary." >&2
exit 1
