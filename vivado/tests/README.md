# Test Suite

Tests for `rules_vivado` Bazel rules covering Verilator simulation, Vivado xsim, IP packaging, custom interface definitions, and full FPGA flows.

All xsim and Vivado tests are tagged `manual` since they require a Vivado installation and license.

## Verilator C++ Tests

### `johnson_counter_test`

Unit test for a Johnson counter (ring shift register) using Verilator and GoogleTest. The counter rotates an 8-bit value left or right, advancing every 8 clock cycles. The test verifies the expected Johnson sequence over 256 cycles.

**Files:** `johnson_counter_test.cc`, `johnson_counter.sv`

```
bazel test //vivado/tests:johnson_counter_test
```

### `weights_replay_test`

Unit test for a ROM-based weights replay module. The module reads 8 hex values from `test.mem` via `$readmemh` and outputs them sequentially, cycling through the weights with each value held for 8 clock cycles. The test verifies two full passes through the weight table (2048 cycles).

**Files:** `weights_replay_test.cc`, `weights_replay.sv`, `test.mem`

```
bazel test //vivado/tests:weights_replay_test
```

## XSim Simulation Tests

### `xsim_smoke_test`

Basic sanity test for the xsim flow. Generates a 100MHz clock, runs for 200 cycles, and checks a trivially-true assertion. Also exercises waveform trace generation.

**Files:** `xsim_smoke_tb.sv`

```
bazel test //vivado/tests:xsim_smoke_test
```

### `stream_fifo_xsim_test`

Functional test of a parametric stream FIFO with separate write and read channels using ready/valid handshaking. The testbench writes 8 entries with sequential addresses and data, verifies the fill level, reads them all back with data integrity checks, and confirms the FIFO is empty.

Demonstrates the `vivado_interface_definition` rule: `stream_fifo_if.sv` defines a custom SystemVerilog interface with `SPIRIT:` annotations, and the IP-XACT metadata flows through `verilog_library` data dependencies.

**Files:** `stream_fifo_tb.sv`, `stream_fifo.sv`, `stream_fifo_if.sv`

```
bazel test //vivado/tests:stream_fifo_xsim_test
```

### `weights_replay_and_save_xsim`

Verifies that nested IP blocks (an IP containing other IPs) work correctly in xsim. The design under test instantiates both `weights_replay_ip` and `weights_ram_ip` via a block design TCL script. The testbench checks that both sub-IPs initialize with identical weight values.

**Files:** `weights_replay_and_save_tb.sv`, `weights_replay_and_save_bd.tcl`

```
bazel test //vivado/tests:weights_replay_and_save_xsim
```

## Error Detection Tests

These tests verify that the xsim infrastructure properly detects failures. Each consists of an xsim test that is *expected to fail*, wrapped by a shell script that inverts the exit code.

### `error_detection_expect_failure_test`

Confirms that `$error` calls in simulation cause xsim to report failure.

**Files:** `error_detection_tb.sv`, `expect_xsim_failure.sh`

### `assert_detection_expect_failure_test`

Confirms that SystemVerilog assertion failures cause xsim to report failure.

**Files:** `assert_detection_tb.sv`, `expect_xsim_failure.sh`

```
bazel test //vivado/tests:all_xsim_tests
```

## Vivado IP Packaging

### `weights_replay_ip`

Packages `weights_replay.sv` as an encrypted Vivado IP core with its `test.mem` data file.

### `weights_ram_ip`

Packages `weights_ram.sv` as an unencrypted Vivado IP core.

### `weights_replay_and_save_ip`

Packages a composite IP that contains both `weights_replay_ip` and `weights_ram_ip` as nested sub-IPs, connected via a block design TCL script (`weights_replay_and_save_bd.tcl`).

## Vivado Flow and Project Targets

### `johnson_counter_vivado`

Full FPGA flow (synthesis through bitstream) for the Johnson counter targeting the ZCU28DR (ZCU111 board). Uses `io_constraints.xdc` for LED pin assignments (8 LEDs, LVCMOS18) and `zcu111_gpio.tcl` for the Zynq MPSoC block design.

**Files:** `johnson_counter_top.sv`, `io_constraints.xdc`, `zcu111_gpio.tcl`

### `johnson_counter_project`

Creates a Vivado project (`.xpr`) for the Johnson counter without running synthesis.

### `weights_replay_vivado`

Full FPGA flow for the weights replay module as a packaged IP block, targeting ZCU28DR.

**Files:** `weights_replay_top.sv`, `zcu111_weights.tcl`

### `weights_replay_project` / `weights_replay_and_save_project`

Create Vivado projects for the weights replay designs with their respective IP dependencies.

## Custom Interface Definitions

These targets demonstrate the `vivado_interface_definition` and `vivado_create_interface_ip` rules for registering custom SystemVerilog interfaces in the Vivado IP catalog.

### `stream_fifo_interface`

Generates IP-XACT metadata for `stream_fifo_if`, a streaming FIFO interface with write channel (addr, data, valid, ready, strobe), read channel (addr, data, valid, ready), and optional status signals (overflow, underflow, fill_level).

**Files:** `stream_fifo_if.sv`

### `bram_read_only_interface` / `bram_write_only_interface`

Generate IP-XACT metadata for separate read-only and write-only BRAM interfaces. The read interface provides addr, en, data, and valid. The write interface provides addr, en, we (byte-write-enable), and data.

**Files:** `bram_read_only_if.sv`, `bram_write_only_if.sv`

### `bram_read_only_interface_ip` / `bram_write_only_interface_ip`

Package the BRAM interface definitions into IP catalog entries that Vivado can use for block design connections and IP customization.

## BRAM Read/Write Splitter

An end-to-end example of custom interfaces used in a complete Vivado block design.

### `bram_read_write_splitter`

Arbitrates between separate read-only and write-only BRAM interface ports, multiplexing them onto a single BRAM port A connection. Write requests have priority over reads.

**Files:** `bram_read_write_splitter.sv`

### `bram_read_write_splitter_wrapper`

IP-packaging wrapper that flattens the SystemVerilog interfaces into individual ports with `X_INTERFACE_INFO` attributes for Vivado. Maps custom `bram_read_only_if`, `bram_write_only_if`, and standard Xilinx BRAM interfaces.

**Files:** `bram_read_write_splitter_wrapper.sv`

### `bram_read_write_splitter_ip`

Packages the wrapper as a Vivado IP block with dependencies on the custom interface IPs.

### `test_reader` / `test_reader_ip`

Example IP that drives a `bram_read_only_if` with sequential read requests and captures returned data.

**Files:** `test_reader.sv`

### `test_writer` / `test_writer_ip`

Example IP that drives a `bram_write_only_if` with sequential write requests (incrementing address and data, all byte lanes enabled).

**Files:** `test_writer.sv`

### `interface_example_project`

Complete Vivado project demonstrating custom interface usage in a block design. Connects `test_reader` and `test_writer` through the `bram_read_write_splitter` to a Xilinx `blk_mem_gen` BRAM IP. The block design is created by `interface_example.tcl`.

**Files:** `interface_example_top.sv`, `interface_example.tcl`

## Environment Scripts

### `xilinx_env.sh`

Sets up the environment for Vivado 2021.2 (`/opt/xilinx/2021.2/Vivado/settings64.sh`, license at `2100@localhost`).

### `xilinx_env_2025_1.sh`

Sets up the environment for Vivado 2025.1. Used by the newer interface and IP tests.

## Support Files

| File | Description |
|------|-------------|
| `test.mem` | Hex memory initialization file (8 values: 00, 05, 0A, 0F, 14, 19, 1E, 28) |
| `io_constraints.xdc` | Pin assignments for 8 LEDs on ZCU111 (LVCMOS18) |
| `zcu111_gpio.tcl` | Zynq MPSoC block design for GPIO on ZCU111 |
| `zcu111_weights.tcl` | Zynq MPSoC block design for weights replay on ZCU111 |
| `weights_replay_and_save_bd.tcl` | Block design connecting weights_replay and weights_ram IPs |
| `interface_example.tcl` | Block design for the custom interface example project |
| `zcu111_gpio.png` | Block design diagram screenshot |
