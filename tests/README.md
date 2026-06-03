# Tests

Rule-behavior coverage for `rules_vivado`.

## Board coverage

The tests target **four boards** chosen to exercise `rules_vivado`'s
meaningfully-distinct code paths without matrix-explosion: three
hobbyist-tier boards for the bulk of coverage, one commercial-tier
board for the Versal-only branch. Every part is supported by
**Vivado ML Standard (the free tier)** so users can reproduce the
tests without a paid license.

| Board | Part | Family | Approx. cost | What it uniquely exercises |
|---|---|---|---|---|
| **Digilent Arty A7-35T** | `xc7a35ticsg324-1L` | Artix-7 (7-series) | ~$150 | Pure-FPGA `.bit`, no Zynq PS, 7-series primitives. Cheapest / most tutorial coverage. |
| **Digilent PYNQ-Z2** | `xc7z020clg400-1` | Zynq-7000 | ~$200 | Zynq-**7000** BD path (`zynq_ps` cell, PS7 vs PSU7 differ in BD address maps + XDC dialect). |
| **Avnet Ultra96-V2** | `xczu3eg-sbva484-1-i` | Zynq UltraScale+ MPSoC | ~$300 | UltraScale+ MPSoC (`zynq_ultra_ps_e` cell) + UltraScale+ synth/place-opt code paths. |
| **Versal Prime** | `xcvm1102-sfva784-2MP-e-S` | Versal Prime | (no board — chip only) | `vivado_device_image` -> `.pdi` (a different Tcl command + output shape from `write_bitstream`). Only way to cover the Versal branch. Prime is the Versal subfamily buildable under Vivado ML Standard; AI Core / Premium require the enterprise seat. |

Boards were picked along three orthogonal axes:

1. **Silicon generation** — 7-series -> UltraScale -> UltraScale+ -> Versal.
   Each generation has distinct synth/place-opt behavior; the ruleset
   handles all four.
2. **PS integration** — none (Arty) -> Zynq-7000 PS7 (PYNQ-Z2) -> Zynq
   UltraScale+ PSU (Ultra96-V2) -> Versal (no PS in the trivial `blink`
   design). Different BD cells and address-map conventions per tier.
3. **Bitstream vs device image** — `.bit` (Arty, PYNQ-Z2, Ultra96) vs
   `.pdi` (Versal Prime). Different Tcl surface, different post-route
   Vivado command.
