// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_if
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: SystemVerilog interface encapsulating dual clock domains,
//              physical RX block stream, decoded TLP streaming egress,
//              and comprehensive link health diagnostics.
// =============================================================================

`ifndef PCIE_IF_SV
`define PCIE_IF_SV

`timescale 1ns / 1ps

interface pcie_if (
  input logic rx_pclk,
  input logic sys_clk
);
  // Resets
  logic         rx_rst_n;
  logic         sys_rst_n;

  // Control & Configuration
  logic         descramble_en;
  logic         seed_load;
  logic [22:0]  seed_val;

  // Physical RX Input
  logic         rx_valid;
  logic [1:0]   rx_sync_hdr;
  logic [127:0] rx_data;

  // Decoded TLP Egress Streaming Interface
  logic         tlp_valid;
  logic         tlp_start;
  logic         tlp_end;
  logic [127:0] tlp_data;
  logic [3:0]   tlp_keep;
  logic [11:0]  tlp_seq_num;
  logic [9:0]   tlp_length_dw;
  logic [127:0] tlp_header;
  logic         tlp_is_4dw;
  logic         tlp_error;
  logic         tlp_lcrc_err;
  logic         tlp_stp_err;

  // Link Integrity & Telemetry Diagnostics
  logic         block_lock;
  logic         sync_header_err;
  logic         link_recovery_req;
  logic         fifo_full;
  logic         fifo_empty;
  logic         fifo_overflow_err;
  logic         fifo_underflow_err;
  logic [5:0]   wr_occupancy;
  logic [5:0]   rd_occupancy;
  logic [31:0]  skp_deleted_cnt;
  logic [31:0]  skp_inserted_cnt;
  logic [31:0]  corrupt_hdr_cnt;
  logic [31:0]  valid_block_cnt;
  logic [31:0]  tlp_success_cnt;
  logic [31:0]  tlp_error_cnt;

  // Real-time Clock Tolerance Drift Parameter (-300 to +300 ppm)
  int           clock_drift_ppm;

  // ---------------------------------------------------------------------------
  // Driver Modport
  // ---------------------------------------------------------------------------
  modport driver_mp (
    input  rx_pclk,
    input  sys_clk,
    output rx_rst_n,
    output sys_rst_n,
    output descramble_en,
    output seed_load,
    output seed_val,
    output rx_valid,
    output rx_sync_hdr,
    output rx_data,
    output clock_drift_ppm
  );

  // ---------------------------------------------------------------------------
  // Monitor Modport
  // ---------------------------------------------------------------------------
  modport monitor_mp (
    input rx_pclk,
    input sys_clk,
    input rx_rst_n,
    input sys_rst_n,
    input descramble_en,
    input rx_valid,
    input rx_sync_hdr,
    input rx_data,
    input tlp_valid,
    input tlp_start,
    input tlp_end,
    input tlp_data,
    input tlp_keep,
    input tlp_seq_num,
    input tlp_length_dw,
    input tlp_header,
    input tlp_is_4dw,
    input tlp_error,
    input tlp_lcrc_err,
    input tlp_stp_err,
    input block_lock,
    input sync_header_err,
    input link_recovery_req,
    input fifo_full,
    input fifo_empty,
    input wr_occupancy,
    input rd_occupancy,
    input skp_deleted_cnt,
    input skp_inserted_cnt,
    input corrupt_hdr_cnt,
    input valid_block_cnt,
    input tlp_success_cnt,
    input tlp_error_cnt,
    input clock_drift_ppm
  );

endinterface : pcie_if

`endif // PCIE_IF_SV
