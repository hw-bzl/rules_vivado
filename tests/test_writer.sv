// Test Writer - drives the write-only BRAM interface with a sequential pattern
//
// Generates a continuous stream of write requests, incrementing address and
// data each clock cycle. Writes full words (all byte enables asserted).

`timescale 1ns / 1ps

module test_writer #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int WE_WIDTH   = DATA_WIDTH / 8
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 100000000, ASSOCIATED_RESET rst, ASSOCIATED_BUSIF wr" *)
    input logic clk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input logic rst,

    // bram_write_only_if master
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr ADDR" *)
    output logic [ADDR_WIDTH-1:0] wr_addr,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr EN" *)
    output logic                  wr_en,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr WE" *)
    output logic [  WE_WIDTH-1:0] wr_we,
    (* X_INTERFACE_INFO = "test_vendor:interfaces:bram_write_only_if:1.0 wr DATA" *)
    output logic [DATA_WIDTH-1:0] wr_data
);

  logic [ADDR_WIDTH-1:0] addr_counter;
  logic [DATA_WIDTH-1:0] data_counter;

  always_ff @(posedge clk) begin
    if (rst) begin
      addr_counter <= '0;
      data_counter <= '0;
      wr_en        <= 1'b0;
      wr_addr      <= '0;
      wr_we        <= '0;
      wr_data      <= '0;
    end else begin
      wr_en <= 1'b1;
      wr_addr <= addr_counter;
      wr_we <= '1;
      wr_data <= data_counter;
      addr_counter <= addr_counter + 1;
      data_counter <= data_counter + 1;
    end
  end

endmodule
