// Test Reader - drives the read-only BRAM interface with a sequential pattern
//
// Generates a continuous stream of read requests, incrementing the address
// each clock cycle. Captures returned data for observability.

`timescale 1ns / 1ps

module test_reader #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_RESET rst, ASSOCIATED_BUSIF rd" *)
    input logic clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input logic rst,

    // bram_read_only_if master
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd ADDR" *)
    output logic [ADDR_WIDTH-1:0] rd_addr,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd EN" *)
    output logic                  rd_en,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd DATA" *)
    input  logic [DATA_WIDTH-1:0] rd_data,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_read_only_if:1.0 rd VALID" *)
    input logic rd_valid
);

  logic [ADDR_WIDTH-1:0] addr_counter;
  logic [DATA_WIDTH-1:0] captured_data;

  always_ff @(posedge clk) begin
    if (rst) begin
      addr_counter  <= '0;
      rd_en         <= 1'b0;
      rd_addr       <= '0;
      captured_data <= '0;
    end else begin
      rd_en <= 1'b1;
      rd_addr <= addr_counter;
      addr_counter <= addr_counter + 1;

      if (rd_valid) captured_data <= rd_data;
    end
  end

endmodule
