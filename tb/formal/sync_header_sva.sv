// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: sync_header_sva
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / Formal Verification
// Description: SVA formal assertions proving 100% detection of corrupted sync
//              headers (2'b00 and 2'b11), zero false alarms on valid headers
//              (2'b01 and 2'b10), and guaranteed Link Recovery thresholding.
// =============================================================================

`timescale 1ns / 1ps

module sync_header_sva
  import pcie_types_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic        rx_valid_i,
  input logic [1:0]  rx_sync_hdr_i,
  input logic        sync_header_err_o,
  input logic        block_lock_o,
  input logic        link_recovery_req_o,
  input logic [31:0] corrupt_hdr_cnt_o,
  input logic [31:0] valid_block_cnt_o,
  input logic [1:0]  state_q,
  input logic [2:0]  consec_err_q
);

  // ===========================================================================
  // PROPERTY 1: 100% Detection of Corrupted Sync Header 2'b00
  // Proves that 2'b00 ALWAYS raises sync_header_err_o in the exact same cycle
  // ===========================================================================
  property p_detect_corrupt_00;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid_i && (rx_sync_hdr_i == SYNC_HDR_ERR_00)) |-> (sync_header_err_o == 1'b1);
  endproperty
  assert_detect_corrupt_00: assert property (p_detect_corrupt_00)
    else $error("[FORMAL ERROR] Corrupted sync header 2'b00 was NOT detected!");

  // ===========================================================================
  // PROPERTY 2: 100% Detection of Corrupted Sync Header 2'b11
  // Proves that 2'b11 ALWAYS raises sync_header_err_o in the exact same cycle
  // ===========================================================================
  property p_detect_corrupt_11;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid_i && (rx_sync_hdr_i == SYNC_HDR_ERR_11)) |-> (sync_header_err_o == 1'b1);
  endproperty
  assert_detect_corrupt_11: assert property (p_detect_corrupt_11)
    else $error("[FORMAL ERROR] Corrupted sync header 2'b11 was NOT detected!");

  // ===========================================================================
  // PROPERTY 3: Zero False Alarms on Valid Data Block 2'b01
  // ===========================================================================
  property p_no_false_alarm_data;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid_i && (rx_sync_hdr_i == SYNC_HDR_DATA)) |-> (sync_header_err_o == 1'b0);
  endproperty
  assert_no_false_alarm_data: assert property (p_no_false_alarm_data)
    else $error("[FORMAL ERROR] False alarm: sync_header_err_o asserted for valid Data Block 2'b01!");

  // ===========================================================================
  // PROPERTY 4: Zero False Alarms on Valid Ordered Set Block 2'b10
  // ===========================================================================
  property p_no_false_alarm_os;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid_i && (rx_sync_hdr_i == SYNC_HDR_ORDERED_SET)) |-> (sync_header_err_o == 1'b0);
  endproperty
  assert_no_false_alarm_os: assert property (p_no_false_alarm_os)
    else $error("[FORMAL ERROR] False alarm: sync_header_err_o asserted for valid Ordered Set 2'b10!");

  // ===========================================================================
  // PROPERTY 5: Telemetry Counter Monotonicity on Corrupted Header
  // ===========================================================================
  property p_corrupt_cnt_increments;
    @(posedge clk) disable iff (!rst_n)
    (rx_valid_i && sync_header_err_o) |=> (corrupt_hdr_cnt_o == $past(corrupt_hdr_cnt_o) + 1'b1);
  endproperty
  assert_corrupt_cnt_increments: assert property (p_corrupt_cnt_increments)
    else $error("[FORMAL ERROR] Corrupted header telemetry counter failed to increment!");

  // ===========================================================================
  // PROPERTY 6: Guaranteed Link Recovery on 4 Consecutive Errors
  // ===========================================================================
  property p_recovery_on_4_consec_errors;
    @(posedge clk) disable iff (!rst_n)
    (block_lock_o && (consec_err_q == 3'd3) && rx_valid_i && sync_header_err_o)
      |-> (link_recovery_req_o == 1'b1);
  endproperty
  assert_recovery_on_4_consec_errors: assert property (p_recovery_on_4_consec_errors)
    else $error("[FORMAL ERROR] Link Recovery not requested after 4 consecutive errors!");

  // ===========================================================================
  // Formal Coverage: Cover state progression and error detections
  // ===========================================================================
  cover_detect_00: cover property (@(posedge clk) disable iff (!rst_n)
    rx_valid_i && (rx_sync_hdr_i == 2'b00));

  cover_detect_11: cover property (@(posedge clk) disable iff (!rst_n)
    rx_valid_i && (rx_sync_hdr_i == 2'b11));

  cover_link_recovery: cover property (@(posedge clk) disable iff (!rst_n)
    link_recovery_req_o);

endmodule : sync_header_sva
