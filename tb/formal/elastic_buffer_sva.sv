// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: elastic_buffer_sva
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / Formal Verification
// Description: JasperGold / SVA formal property suite proving zero pointer
//              inversion, monotonic Gray-code progression, no overflow/underflow,
//              and deterministic SKP insertion/deletion watermark triggers.
// =============================================================================

`timescale 1ns / 1ps

module elastic_buffer_sva
  import pcie_types_pkg::*;
#(
  parameter int unsigned DEPTH   = FIFO_DEPTH,
  parameter int unsigned HIGH_WM = HIGH_WATERMARK,
  parameter int unsigned LOW_WM  = LOW_WATERMARK,
  parameter int unsigned ADDR_W  = $clog2(DEPTH)
)(
  input logic              wr_clk,
  input logic              wr_rst_n,
  input logic              wr_valid_i,
  input logic [1:0]        wr_sync_hdr_i,
  input logic              wr_is_skp_i,
  input logic              fifo_full_o,
  input logic              fifo_overflow_err_o,
  input logic [ADDR_W:0]   wr_occupancy_o,
  input logic [ADDR_W:0]   wr_ptr_bin_q,
  input logic [ADDR_W:0]   wr_ptr_bin_d,
  input logic [ADDR_W:0]   wr_ptr_gray_q,
  input logic [ADDR_W:0]   wr_ptr_gray_d,
  input logic              wr_fifo_en,
  input logic              drop_skp_condition,

  input logic              rd_clk,
  input logic              rd_rst_n,
  input logic              rd_ready_i,
  input logic              rd_valid_o,
  input logic              fifo_empty_o,
  input logic              fifo_underflow_err_o,
  input logic [ADDR_W:0]   rd_occupancy_o,
  input logic [ADDR_W:0]   rd_ptr_bin_q,
  input logic [ADDR_W:0]   rd_ptr_bin_d,
  input logic [ADDR_W:0]   rd_ptr_gray_q,
  input logic [ADDR_W:0]   rd_ptr_gray_d,
  input logic              rd_fifo_en,
  input logic              duplicate_skp_condition
);

  // ---------------------------------------------------------------------------
  // Helper: Hamming Distance between two vectors
  // ---------------------------------------------------------------------------
  function automatic int unsigned hamming_dist(input logic [ADDR_W:0] a, input logic [ADDR_W:0] b);
    return $countones(a ^ b);
  endfunction

  // ===========================================================================
  // PROPERTY 1: Monotonic Write Pointer Progression (Zero Pointer Inversion)
  // Proves that wr_ptr_bin either increments by 1 or holds its value. Never decrements!
  // ===========================================================================
  property p_wr_ptr_monotonic;
    @(posedge wr_clk) disable iff (!wr_rst_n)
    (wr_ptr_bin_d == wr_ptr_bin_q) || (wr_ptr_bin_d == wr_ptr_bin_q + 1'b1);
  endproperty
  assert_wr_ptr_monotonic: assert property (p_wr_ptr_monotonic)
    else $error("[FORMAL ERROR] Write pointer inversion detected: non-monotonic progression!");

  // ===========================================================================
  // PROPERTY 2: Gray-Code Single-Bit Transition (Hamming Distance <= 1)
  // Proves that Gray-coded write pointer changes at most 1 bit per clock edge.
  // ===========================================================================
  property p_wr_gray_hamming;
    @(posedge wr_clk) disable iff (!wr_rst_n)
    hamming_dist(wr_ptr_gray_d, wr_ptr_gray_q) <= 1;
  endproperty
  assert_wr_gray_hamming: assert property (p_wr_gray_hamming)
    else $error("[FORMAL ERROR] Gray code transition violation: Hamming distance > 1 on wr_ptr!");

  // ===========================================================================
  // PROPERTY 3: Monotonic Read Pointer Progression (Zero Pointer Inversion)
  // Proves that rd_ptr_bin either increments by 1 or holds its value. Never decrements!
  // ===========================================================================
  property p_rd_ptr_monotonic;
    @(posedge rd_clk) disable iff (!rd_rst_n)
    (rd_ptr_bin_d == rd_ptr_bin_q) || (rd_ptr_bin_d == rd_ptr_bin_q + 1'b1);
  endproperty
  assert_rd_ptr_monotonic: assert property (p_rd_ptr_monotonic)
    else $error("[FORMAL ERROR] Read pointer inversion detected: non-monotonic progression!");

  // ===========================================================================
  // PROPERTY 4: Gray-Code Single-Bit Transition on Read Pointer
  // ===========================================================================
  property p_rd_gray_hamming;
    @(posedge rd_clk) disable iff (!rd_rst_n)
    hamming_dist(rd_ptr_gray_d, rd_ptr_gray_q) <= 1;
  endproperty
  assert_rd_gray_hamming: assert property (p_rd_gray_hamming)
    else $error("[FORMAL ERROR] Gray code transition violation: Hamming distance > 1 on rd_ptr!");

  // ===========================================================================
  // PROPERTY 5: No FIFO Overflow
  // Proves that memory write is never enabled when FIFO is full
  // ===========================================================================
  property p_no_overflow;
    @(posedge wr_clk) disable iff (!wr_rst_n)
    fifo_full_o |-> !wr_fifo_en;
  endproperty
  assert_no_overflow: assert property (p_no_overflow)
    else $error("[FORMAL ERROR] FIFO Overflow violation: wr_fifo_en asserted while full!");

  // ===========================================================================
  // PROPERTY 6: No FIFO Underflow
  // Proves that read enable is never asserted when FIFO is empty
  // ===========================================================================
  property p_no_underflow;
    @(posedge rd_clk) disable iff (!rd_rst_n)
    fifo_empty_o |-> !rd_fifo_en;
  endproperty
  assert_no_underflow: assert property (p_no_underflow)
    else $error("[FORMAL ERROR] FIFO Underflow violation: rd_fifo_en asserted while empty!");

  // ===========================================================================
  // PROPERTY 7: SKP Ordered Set Deletion Trigger Verification
  // Proves that whenever a SKP arrives with occupancy >= HIGH_WM, it is dropped
  // ===========================================================================
  property p_skp_deletion_trigger;
    @(posedge wr_clk) disable iff (!wr_rst_n)
    (wr_valid_i && wr_is_skp_i && (wr_occupancy_o >= HIGH_WM)) |-> (drop_skp_condition && !wr_fifo_en);
  endproperty
  assert_skp_deletion_trigger: assert property (p_skp_deletion_trigger)
    else $error("[FORMAL ERROR] SKP Deletion trigger failed: SKP OS was not dropped above HIGH_WM!");

  // ===========================================================================
  // PROPERTY 8: SKP Ordered Set Insertion Trigger Verification
  // Proves that when occupancy <= LOW_WM and reading SKP, read pointer holds
  // ===========================================================================
  property p_skp_insertion_trigger;
    @(posedge rd_clk) disable iff (!rd_rst_n)
    (duplicate_skp_condition) |-> (!rd_fifo_en && (rd_ptr_bin_d == rd_ptr_bin_q));
  endproperty
  assert_skp_insertion_trigger: assert property (p_skp_insertion_trigger)
    else $error("[FORMAL ERROR] SKP Insertion trigger failed: read pointer did not hold!");

  // ===========================================================================
  // Formal Coverage: Cover high/low watermark hit and SKP compensation
  // ===========================================================================
  cover_high_watermark: cover property (@(posedge wr_clk) disable iff (!wr_rst_n)
    wr_occupancy_o >= HIGH_WM);

  cover_low_watermark: cover property (@(posedge rd_clk) disable iff (!rd_rst_n)
    rd_occupancy_o <= LOW_WM);

  cover_skp_deleted: cover property (@(posedge wr_clk) disable iff (!wr_rst_n)
    drop_skp_condition);

  cover_skp_duplicated: cover property (@(posedge rd_clk) disable iff (!rd_rst_n)
    duplicate_skp_condition);

endmodule : elastic_buffer_sva
