#!/usr/bin/env bash
# Default `vivado_toolchain.vivado` script — invokes `vivado` from the
# exec platform's PATH. Provided as a migration default so existing
# toolchains that relied on `PATH`-discovered Vivado keep working without
# every consumer authoring a shim up front. New toolchains should provide
# their own `vivado` attr pointing at a shim that hard-codes the install
# path (e.g. baked into a container image).
exec vivado "$@"
