// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: tb_top
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: Top-level UVM verification testbench with dual clock generation,
//              dynamic PPM clock jitter modulation (+/- 300 ppm), DUT hookup,
//              and waveform dumping.
// =============================================================================

`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import pcie_types_pkg::*;
`include "pcie_if.sv"
`include "pcie_tests.sv"

module tb_top;

  // ---------------------------------------------------------------------------
  // Clock Signals & Runtime Variable Frequency Generator
  // ---------------------------------------------------------------------------
  logic sys_clk = 0;
  logic rx_pclk = 0;

  // sys_clk: Fixed 250 MHz Reference Clock (Period = 4.0 ns)
  always #2.0ns sys_clk = ~sys_clk;

  // rx_pclk: Dynamically Modulated Recovered Clock (+/- 300 ppm tolerance)
  real rx_half_period_ns = 2.0;

  always @(u_if.clock_drift_ppm) begin
    // Period = 4.0 / (1.0 + ppm * 1e-6)
    rx_half_period_ns = (4.0 / (1.0 + real'(u_if.clock_drift_ppm) * 1.0e-6)) / 2.0;
  end

  always begin
    #(rx_half_period_ns * 1.0ns) rx_pclk = ~rx_pclk;
  end

  // ---------------------------------------------------------------------------
  // Interface Instantiation
  // ---------------------------------------------------------------------------
  pcie_if u_if (
    .rx_pclk (rx_pclk),
    .sys_clk (sys_clk)
  );

  // ---------------------------------------------------------------------------
  // DUT Instantiation
  // ---------------------------------------------------------------------------
  pcie_gen3_phy_decoder_top u_dut (
    .rx_pclk             (rx_pclk),
    .rx_rst_n            (u_if.rx_rst_n),
    .sys_clk             (sys_clk),
    .sys_rst_n           (u_if.sys_rst_n),

    .descramble_en_i     (u_if.descramble_en),
    .seed_load_i         (u_if.seed_load),
    .seed_val_i          (u_if.seed_val),

    .rx_valid_i          (u_if.rx_valid),
    .rx_sync_hdr_i       (u_if.rx_sync_hdr),
    .rx_data_i           (u_if.rx_data),

    .tlp_valid_o         (u_if.tlp_valid),
    .tlp_start_o         (u_if.tlp_start),
    .tlp_end_o           (u_if.tlp_end),
    .tlp_data_o          (u_if.tlp_data),
    .tlp_keep_o          (u_if.tlp_keep),
    .tlp_seq_num_o       (u_if.tlp_seq_num),
    .tlp_length_dw_o     (u_if.tlp_length_dw),
    .tlp_header_o        (u_if.tlp_header),
    .tlp_is_4dw_o        (u_if.tlp_is_4dw),
    .tlp_error_o         (u_if.tlp_error),
    .tlp_lcrc_err_o      (u_if.tlp_lcrc_err),
    .tlp_stp_err_o       (u_if.tlp_stp_err),

    .block_lock_o        (u_if.block_lock),
    .sync_header_err_o   (u_if.sync_header_err),
    .link_recovery_req_o (u_if.link_recovery_req),
    .fifo_full_o         (u_if.fifo_full),
    .fifo_empty_o        (u_if.fifo_empty),
    .fifo_overflow_err_o (u_if.fifo_overflow_err),
    .fifo_underflow_err_o(u_if.fifo_underflow_err),
    .wr_occupancy_o      (u_if.wr_occupancy),
    .rd_occupancy_o      (u_if.rd_occupancy),
    .skp_deleted_cnt_o   (u_if.skp_deleted_cnt),
    .skp_inserted_cnt_o  (u_if.skp_inserted_cnt),
    .corrupt_hdr_cnt_o   (u_if.corrupt_hdr_cnt),
    .valid_block_cnt_o   (u_if.valid_block_cnt),
    .tlp_success_cnt_o   (u_if.tlp_success_cnt),
    .tlp_error_cnt_o     (u_if.tlp_error_cnt)
  );

  // ---------------------------------------------------------------------------
  // Reset Generation & UVM Testbench Launch
  // ---------------------------------------------------------------------------
  initial begin
    // Initialize resets
    u_if.rx_rst_n  = 1'b0;
    u_if.sys_rst_n = 1'b0;

    // Register virtual interface in config_db
    uvm_config_db#(virtual pcie_if)::set(null, "*", "vif", u_if);

    // Waveform dump setup
    $dumpfile("pcie_uvm_waves.vcd");
    $dumpvars(0, tb_top);

    // Assert reset for 20 ns
    #20ns;
    @(posedge rx_pclk);
    u_if.rx_rst_n  = 1'b1;
    u_if.sys_rst_n = 1'b1;

    // Launch UVM test execution
    run_test();
  end

endmodule : tb_top
