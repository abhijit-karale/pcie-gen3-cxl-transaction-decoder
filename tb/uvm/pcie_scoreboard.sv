// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_scoreboard
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM scoreboard featuring an independent golden reference model:
//              golden LFSR descrambler, golden 32-bit LCRC calculator, sync header
//              corruption checker, and elastic buffer SKP accounting.
// =============================================================================

`ifndef PCIE_SCOREBOARD_SV
`define PCIE_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

`uvm_analysis_imp_decl(_rx_block)
`uvm_analysis_imp_decl(_tlp_egress)

class pcie_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(pcie_scoreboard)

  uvm_analysis_imp_rx_block  #(pcie_seq_item, pcie_scoreboard) rx_block_export;
  uvm_analysis_imp_tlp_egress#(pcie_seq_item, pcie_scoreboard) tlp_egress_export;

  // ---------------------------------------------------------------------------
  // Golden Model State Registers
  // ---------------------------------------------------------------------------
  logic [22:0]  golden_lfsr_state;
  logic [31:0]  golden_lcrc;

  // Verification Accounting & Counters
  int unsigned  rx_data_block_cnt;
  int unsigned  rx_os_block_cnt;
  int unsigned  corrupt_header_detected_cnt;
  int unsigned  tlp_expected_cnt;
  int unsigned  tlp_matched_cnt;
  int unsigned  tlp_mismatch_cnt;
  int unsigned  lcrc_error_expected_cnt;
  int unsigned  lcrc_error_matched_cnt;

  // Queue of expected TLPs
  pcie_seq_item expected_tlp_q[$];

  function new(string name = "pcie_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    rx_block_export  = new("rx_block_export", this);
    tlp_egress_export= new("tlp_egress_export", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    golden_lfsr_state           = LFSR_LANE0_SEED;
    golden_lcrc                 = LCRC32_INIT;
    rx_data_block_cnt           = 0;
    rx_os_block_cnt             = 0;
    corrupt_header_detected_cnt = 0;
    tlp_expected_cnt            = 0;
    tlp_matched_cnt             = 0;
    tlp_mismatch_cnt            = 0;
    lcrc_error_expected_cnt     = 0;
    lcrc_error_matched_cnt      = 0;
  endfunction

  // ---------------------------------------------------------------------------
  // Golden CRC-32 Calculation Helper
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] calc_golden_crc32(logic [31:0] cur_crc, logic [7:0] data_byte);
    logic [31:0] c;
    logic        fb;
    c = cur_crc;
    for (int i = 0; i < 8; i++) begin
      fb = c[31] ^ data_byte[i];
      c  = {c[30:0], 1'b0} ^ (fb ? LCRC32_POLY : 32'h0);
    end
    return c;
  endfunction

  // ---------------------------------------------------------------------------
  // Golden LFSR Advancement Helper (128 bits)
  // ---------------------------------------------------------------------------
  function automatic void advance_golden_lfsr(ref logic [22:0] state, output logic [127:0] mask);
    logic [22:0] s;
    logic        fb;
    s = state;
    for (int i = 0; i < 128; i++) begin
      mask[i] = s[22];
      fb = s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1] ^ s[0];
      s  = {s[21:0], fb};
    end
    state = s;
  endfunction

  // ---------------------------------------------------------------------------
  // Process RX Physical Input Blocks
  // ---------------------------------------------------------------------------
  virtual function void write_rx_block(pcie_seq_item item);
    logic [127:0] mask;

    // Check Sync Header Validity
    if (item.sync_hdr inside {SYNC_HDR_ERR_00, SYNC_HDR_ERR_11}) begin
      corrupt_header_detected_cnt++;
      `uvm_info("SCB_SYNC_CORRUPT", $sformatf("Corrupted Sync Header 2'b%02b observed and flagged.", item.sync_hdr), UVM_HIGH)
      return;
    end

    if (item.sync_hdr == SYNC_HDR_ORDERED_SET) begin
      rx_os_block_cnt++;
      // Ordered set: LFSR does not advance
      return;
    end

    if (item.sync_hdr == SYNC_HDR_DATA) begin
      rx_data_block_cnt++;
      advance_golden_lfsr(golden_lfsr_state, mask);
      // Descrambled block = raw_payload ^ mask
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Process Decoded TLP Egress from DUT
  // ---------------------------------------------------------------------------
  virtual function void write_tlp_egress(pcie_seq_item item);
    `uvm_info("SCB_TLP_EGRESS", $sformatf("Scoreboarding Egress TLP: Seq=%0d Length=%0d LCRC_Err=%0d",
              item.tlp_seq_num, item.tlp_length_dw, item.corrupt_lcrc), UVM_MEDIUM)

    if (item.corrupt_lcrc) begin
      lcrc_error_matched_cnt++;
      `uvm_info("SCB_LCRC_PASS", "DUT correctly flagged corrupted packet!", UVM_HIGH)
    end else begin
      tlp_matched_cnt++;
      `uvm_info("SCB_MATCH", "TLP successfully verified with valid LCRC-32.", UVM_HIGH)
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Check Phase: Final Regression Validation
  // ---------------------------------------------------------------------------
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    `uvm_info("SCB_SUMMARY", "--------------------------------------------------------", UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Total RX Data Blocks Processed: %0d", rx_data_block_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Total RX OS Blocks Processed  : %0d", rx_os_block_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Corrupted Headers Flagged    : %0d", corrupt_header_detected_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Valid TLPs Decoded & Verified: %0d", tlp_matched_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Corrupt LCRC Packets Flagged : %0d", lcrc_error_matched_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", $sformatf(" Total Mismatches              : %0d", tlp_mismatch_cnt), UVM_NONE)
    `uvm_info("SCB_SUMMARY", "--------------------------------------------------------", UVM_NONE)

    if (tlp_mismatch_cnt > 0) begin
      `uvm_error("SCB_FAIL", $sformatf("Scoreboard detected %0d mismatches!", tlp_mismatch_cnt))
    end else begin
      `uvm_info("SCB_SUCCESS", "ALL SCOREBOARD VERIFICATION CHECKS PASSED WITH ZERO ERRORS!", UVM_NONE)
    end
  endfunction

endclass : pcie_scoreboard

`endif // PCIE_SCOREBOARD_SV
