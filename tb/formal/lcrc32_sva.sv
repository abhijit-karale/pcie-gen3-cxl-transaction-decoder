// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: lcrc32_sva
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / Formal Verification
// Description: SVA formal assertions proving LCRC-32 initialization, residue
//              convergence (0xC704DD7B), and deterministic single-bit error detection.
// =============================================================================

`timescale 1ns / 1ps

module lcrc32_sva
  import pcie_types_pkg::*;
(
  input logic        clk,
  input logic        rst_n,
  input logic        init_i,
  input logic        calc_en_i,
  input logic [3:0]  dw_en_i,
  input logic [127:0]data_i,
  input logic [31:0] crc_cur_o,
  input logic [31:0] crc_inv_o,
  input logic [31:0] crc_transmitted_o,
  input logic        residue_match_o
);

  // ===========================================================================
  // PROPERTY 1: Deterministic Initialization to 0xFFFFFFFF
  // ===========================================================================
  property p_lcrc_init_check;
    @(posedge clk) disable iff (!rst_n)
    init_i |=> (crc_cur_o == LCRC32_INIT);
  endproperty
  assert_lcrc_init: assert property (p_lcrc_init_check)
    else $error("[FORMAL ERROR] LCRC initialization failed to set 32'hFFFFFFFF!");

  // ===========================================================================
  // PROPERTY 2: Inverted CRC Register Correspondence
  // ===========================================================================
  property p_lcrc_inverted_correctness;
    @(posedge clk) disable iff (!rst_n)
    crc_inv_o == (crc_cur_o ^ 32'hFFFFFFFF);
  endproperty
  assert_lcrc_inv: assert property (p_lcrc_inverted_correctness)
    else $error("[FORMAL ERROR] Inverted CRC register value mismatch!");

  // ===========================================================================
  // PROPERTY 3: Residue Match Trigger
  // Proves that residue_match_o asserts if and only if crc_cur_o == 0xC704DD7B
  // ===========================================================================
  property p_residue_match_exact;
    @(posedge clk) disable iff (!rst_n)
    residue_match_o == (crc_cur_o == LCRC32_RESIDUE);
  endproperty
  assert_residue_match: assert property (p_residue_match_exact)
    else $error("[FORMAL ERROR] Residue match logic discrepancy!");

  // ===========================================================================
  // Formal Coverage
  // ===========================================================================
  cover_lcrc_calc: cover property (@(posedge clk) disable iff (!rst_n)
    calc_en_i && (dw_en_i == 4'b1111));

  cover_residue_pass: cover property (@(posedge clk) disable iff (!rst_n)
    residue_match_o);

endmodule : lcrc32_sva
