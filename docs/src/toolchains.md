# Toolchains

`rules_vivado` resolves the Xilinx Vivado install through Bazel
toolchain resolution. You declare a
[`vivado_toolchain`](./vivado_toolchain.md), wrap it in `toolchain(...)`,
and register it from `MODULE.bazel`. Every `vivado_*` rule then picks
it up automatically — there is no per-target `xilinx_env` to thread
through.

Registering a toolchain is **required**.

## Getting Vivado

A toolchain says *how* to run Vivado; it does not put Vivado on the
machine. Three ways to close that gap, each documented by its own
project:

- **Bring your own install.** Point the toolchain's `vivado` shim at
  an install you manage yourself, on the host or in a golden image.
  Works wherever that path exists; not portable to remote execution
  on its own.
- **A container image you build.**
  [`vivado-docker`](https://github.com/filmil/vivado-docker) is a
  recipe that runs AMD's installer inside an Ubuntu image from an
  installer archive you download. Its README covers the build, the
  component selection, and the licensing constraints. This is the
  only option that supports remote execution, since the image can
  be named on an execution platform and pulled by every worker.
- **A Bazel-provisioned install.**
  [`toolchains_vivado`](https://github.com/filmil/bazel_toolchains_vivado)
  is a module whose extension installs Vivado from an installer
  archive into a per-machine cache and registers the resulting
  toolchain for you, so there is no shim or `register_toolchains`
  call to write. Its README covers setup, the install cache, and its
  limits: Linux only, and the install is referenced by absolute path,
  so it does not work under remote execution.

Neither external project ships Vivado. In every case you download the
installer from AMD under your own account, accept the EULA yourself,
and keep the result private. Vivado ML Standard needs no license
server, so `requires_network = False` is the right setting for it.

### Running actions in a container image

With a container image, either run Bazel inside the container, or keep
Bazel on the host and route the Vivado actions through Bazel's docker
sandbox. The mnemonic list is this ruleset's; everything else is
standard Bazel:

```text
build --experimental_enable_docker_sandbox
build --experimental_docker_image=<your-image>:<tag>

build --strategy=VivadoBlockDesign=docker
build --strategy=VivadoCompileSimlib=docker
build --strategy=VivadoCreateInterfaceIp=docker
build --strategy=VivadoCreateIp=docker
build --strategy=VivadoExportSimulation=docker
build --strategy=VivadoPlace=docker
build --strategy=VivadoPlaceOpt=docker
build --strategy=VivadoProjectExport=docker
build --strategy=VivadoRoute=docker
build --strategy=VivadoSynth=docker
build --strategy=VivadoSynthOpt=docker
build --strategy=VivadoWriteBitstream=docker
build --strategy=VivadoWriteDebugProbes=docker
build --strategy=VivadoWriteDeviceImage=docker
build --strategy=VivadoWriteHwPlatform=docker
build --strategy=VivadoXci=docker
build --strategy=VivadoXSimExport=docker

# vivado_xsim_test runs xsim at test time, so test spawns need the
# image too.
test --strategy=VivadoXSimExport=docker
test --spawn_strategy=docker,sandboxed,local
```

The sandbox strips `PATH`, so the shim must restore it (or source the
install's `settings64.sh`) before it `exec`s `vivado`. For remote
execution, name the image on the execution platform instead of in a
bazelrc:

```python
platform(
    name = "vivado_rbe",
    constraint_values = ["@rules_vivado//vivado/constraints/version:2025.2"],
    exec_properties = {"container-image": "docker://<registry>/<image>@sha256:<digest>"},
    parents = ["@platforms//host"],
)
```

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
[`//vivado/constraints/version`](https://github.com/hw-bzl/rules_vivado/blob/main/vivado/constraints/version/BUILD.bazel).
Each constraint corresponds to one entry in `VIVADO_VERSIONS` (defined
in
[`//vivado/private:versions.bzl`](https://github.com/hw-bzl/rules_vivado/blob/main/vivado/private/versions.bzl)).
The [`vivado_toolchain`](./vivado_toolchain.md) docstring has the
full multi-version walkthrough — `platform(...)` setup,
`register_execution_platforms`, and the `--platforms` switch.

Constraints are the only mechanism — there is no parallel build-setting
/ flag-driven path. This keeps per-version metadata (constraints,
`exec_properties` like `container-image`) all on the platform object
where it belongs and avoids the two-sources-of-truth problem.

## Reference

See [`vivado_toolchain`](./vivado_toolchain.md) for the full attribute
set and [`VivadoToolchainInfo`](./vivado_providers.md) for the
resolved provider that downstream rules consume.
