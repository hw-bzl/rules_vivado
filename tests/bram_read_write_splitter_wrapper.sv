// BRAM Read/Write Splitter - IP Packaging Wrapper
//
// Top-level module with X_INTERFACE directives for Vivado IP packaging.
// Wraps bram_read_write_splitter with flattened ports so Vivado can
// recognize the custom bus interfaces and BRAM port.
//
// Interfaces:
//   rd   - bram_read_only_if  (slave) : read requests from user
//   wr   - bram_write_only_if (slave) : write requests from user
//   bram - xilinx BRAM port A (master): drives blk_mem_gen

`timescale 1ns / 1ps

module bram_read_write_splitter_wrapper #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int WE_WIDTH   = DATA_WIDTH / 8
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_RESET rst, ASSOCIATED_BUSIF rd:wr:bram" *)
    input logic clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input logic rst,

    // Read-only BRAM interface (slave)
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd ADDR" *)
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd EN" *)
    input  logic                  rd_en,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd DATA" *)
    output logic [DATA_WIDTH-1:0] rd_data,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd VALID" *)
    output logic rd_valid,

    // Write-only BRAM interface (slave)
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr ADDR" *)
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr EN" *)
    input  logic                  wr_en,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr WE" *)
    input  logic [  WE_WIDTH-1:0] wr_we,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr DATA" *)
    input logic [DATA_WIDTH-1:0] wr_data,

    // BRAM Port A (master - drives blk_mem_gen)
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram ADDR" *)
    output logic [ADDR_WIDTH-1:0] bram_addr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram CLK" *)
    output logic bram_clk, (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram DIN" *)
    output logic [DATA_WIDTH-1:0] bram_din,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram DOUT" *)
    input  logic [DATA_WIDTH-1:0] bram_dout,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram EN" *)
    output logic bram_en, (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram RST" *)
    output logic                  bram_rst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 bram WE" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME bram, MASTER_TYPE BRAM_CTRL" *)
    output logic [WE_WIDTH-1:0] bram_we,

    input logic bram_rsta_busy
);

  // Internal SV interfaces
  bram_read_only_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) rd_if ();

  bram_write_only_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .WE_WIDTH  (WE_WIDTH)
  ) wr_if ();

  // Connect flat read ports to interface
  assign rd_if.addr = rd_addr;
  assign rd_if.en   = rd_en;
  assign rd_data    = rd_if.data;
  assign rd_valid   = rd_if.valid;

  // Connect flat write ports to interface
  assign wr_if.addr = wr_addr;
  assign wr_if.en   = wr_en;
  assign wr_if.we   = wr_we;
  assign wr_if.data = wr_data;

  // Instantiate the splitter core
  bram_read_write_splitter #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .WE_WIDTH  (WE_WIDTH)
  ) splitter_inst (
      .clk(clk),
      .rst(rst),
      .rd(rd_if.slave),
      .wr(wr_if.slave),
      .bram_addr(bram_addr),
      .bram_clk(bram_clk),
      .bram_din(bram_din),
      .bram_dout(bram_dout),
      .bram_en(bram_en),
      .bram_rst(bram_rst),
      .bram_we(bram_we),
      .bram_rsta_busy(bram_rsta_busy)
  );

endmodule
