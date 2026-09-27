// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_descrambler_lfsr
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: Parallel 128-bit LFSR pseudo-random descrambler implementing
//              polynomial G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1.
//              Ordered Sets bypass descrambling. Fully synthesizable unrolled logic.
// =============================================================================

`timescale 1ns / 1ps

module pcie_descrambler_lfsr
  import pcie_types_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,

  // Configuration & Control
  input  logic         descramble_en_i,
  input  logic         seed_load_i,
  input  logic [22:0]  seed_val_i,

  // Input from Sync Header Aligner
  input  logic         aligner_valid_i,
  input  logic [1:0]   aligner_sync_hdr_i,
  input  logic [127:0] aligner_data_i,
  input  logic         aligner_is_data_i,
  input  logic         aligner_is_os_i,

  // Descrambled Egress to Elastic Buffer
  output logic         descrambler_valid_o,
  output logic [1:0]   descrambler_sync_hdr_o,
  output logic [127:0] descrambler_data_o,
  output logic         descrambler_is_data_o,
  output logic         descrambler_is_os_o,
  output logic         descrambler_is_skp_o,
  output logic [22:0]  lfsr_state_o
);

  // ---------------------------------------------------------------------------
  // LFSR State Register
  // ---------------------------------------------------------------------------
  logic [22:0] lfsr_state_q, lfsr_state_d;
  logic [22:0] lfsr_next_state;
  logic [127:0]prbs_mask;

  assign lfsr_state_o = lfsr_state_q;

  // ---------------------------------------------------------------------------
  // Detection of SKP Ordered Set inside Ordered Set blocks
  // In PCIe Gen3, Symbol 0 to Symbol 3 of SKP OS contain 8'hAA
  // ---------------------------------------------------------------------------
  logic is_skp_os;
  assign is_skp_os = aligner_is_os_i && (aligner_data_i[31:0] == SKP_PATTERN_32);

  // ---------------------------------------------------------------------------
  // Parallel 128-bit LFSR Combinational Unrolling Function
  // Polynomial: G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
  // Fibonacci feedback: s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1] ^ s[0]
  // ---------------------------------------------------------------------------
  function automatic void advance_lfsr_128b (
    input  logic [22:0]  s_in,
    output logic [22:0]  s_out,
    output logic [127:0] mask_out
  );
    logic [22:0] s;
    logic        fb;

    s = s_in;
    for (int i = 0; i < 128; i++) begin
      mask_out[i] = s[22];
      fb = s[22] ^ s[20] ^ s[15] ^ s[7] ^ s[4] ^ s[1] ^ s[0];
      s  = {s[21:0], fb};
    end
    s_out = s;
  endfunction

  // Evaluate parallel PRBS mask and next state
  always_comb begin
    advance_lfsr_128b(lfsr_state_q, lfsr_next_state, prbs_mask);
  end

  // ---------------------------------------------------------------------------
  // LFSR State Update Logic
  // ---------------------------------------------------------------------------
  always_comb begin
    lfsr_state_d = lfsr_state_q;

    if (seed_load_i) begin
      lfsr_state_d = seed_val_i;
    end else if (aligner_valid_i) begin
      if (aligner_is_data_i && descramble_en_i) begin
        // Data Block: LFSR advances 128 bits
        lfsr_state_d = lfsr_next_state;
      end else if (is_skp_os) begin
        // SKP Ordered Set: maintains seed or resyncs per spec
        lfsr_state_d = lfsr_state_q;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Pipeline Registers & Output Data Formation
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr_state_q           <= LFSR_LANE0_SEED;
      descrambler_valid_o    <= 1'b0;
      descrambler_sync_hdr_o <= 2'b00;
      descrambler_data_o     <= '0;
      descrambler_is_data_o  <= 1'b0;
      descrambler_is_os_o    <= 1'b0;
      descrambler_is_skp_o   <= 1'b0;
    end else begin
      lfsr_state_q <= lfsr_state_d;

      descrambler_valid_o    <= aligner_valid_i;
      descrambler_sync_hdr_o <= aligner_sync_hdr_i;
      descrambler_is_data_o  <= aligner_is_data_i;
      descrambler_is_os_o    <= aligner_is_os_i;
      descrambler_is_skp_o   <= is_skp_os;

      if (aligner_valid_i) begin
        if (aligner_is_data_i && descramble_en_i) begin
          // XOR ciphertext with parallel 128-bit PRBS mask
          descrambler_data_o <= aligner_data_i ^ prbs_mask;
        end else begin
          // Bypass descrambling for Ordered Sets or when disabled
          descrambler_data_o <= aligner_data_i;
        end
      end else begin
        descrambler_data_o <= '0;
      end
    end
  end

endmodule : pcie_descrambler_lfsr
