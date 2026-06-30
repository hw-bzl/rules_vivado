# Toolchains

`rules_vivado` resolves the Xilinx Vivado install through Bazel
toolchain resolution. You declare a
[`vivado_toolchain`](./vivado_toolchain.md), wrap it in `toolchain(...)`,
and register it from `MODULE.bazel`. Every `vivado_*` rule then picks
it up automatically — there is no per-target `xilinx_env` to thread
through.

Registering a toolchain is **required**.

## Implementing a toolchain

See [`vivado_toolchain`](./vivado_toolchain.md) — the rule's docstring
has the worked quickstart, attribute reference, and the `env` vs
`xilinx_env` framing.

## Network vs. node-locked licenses

`vivado_toolchain.requires_network` defaults to `True`, which is
correct for a floating/network license server
(`XILINXD_LICENSE_FILE=PORT@HOST`). It sets the `requires-network`
execution requirement on every `vivado_*` action.

Set it to `False` for license-free editions (Vivado ML Standard /
WebPACK) or for node-locked `.lic` files read from disk. Sandboxed and
remote-execution builds need network disabled to be reproducible
without the license server, so be deliberate here.

## Constraining toolchains

To run multiple Vivado versions side-by-side, gate each
`vivado_toolchain` with one of the per-version `constraint_value`s in
[`//vivado/constraints/BUILD.bazel`](https://github.com/hw-bzl/rules_vivado/blob/main/vivado/constraints/BUILD.bazel).
Each constraint corresponds to one entry in `VIVADO_VERSIONS` (defined
in
[`//vivado/private:versions.bzl`](https://github.com/hw-bzl/rules_vivado/blob/main/vivado/private/versions.bzl)).
The [`vivado_toolchain`](./vivado_toolchain.md) docstring has the
full multi-version walkthrough — `platform(...)` setup,
`register_execution_platforms`, and the `--platforms` switch.

For per-target switching without a global flag, use a wrapper rule
with `cfg = transition(...)`; see
[`tests/transition.bzl`](https://github.com/hw-bzl/rules_vivado/blob/main/tests/transition.bzl)
for a `with_vivado_version` wrapper that takes a list of targets and
pins the version for the whole group.

Constraints are the only mechanism — there is no parallel build-setting
/ flag-driven path. This keeps per-version metadata (constraints,
`exec_properties` like `container-image`) all on the platform object
where it belongs and avoids the two-sources-of-truth problem.

## Reference

See [`vivado_toolchain`](./vivado_toolchain.md) for the full attribute
set and [`VivadoToolchainInfo`](./vivado_providers.md) for the
resolved provider that downstream rules consume.
