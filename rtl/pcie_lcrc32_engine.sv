// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_lcrc32_engine
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: High-speed parallel 32-bit Link CRC (LCRC-32) computation engine.
//              Polynomial: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 +
//                          x^10 + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1 (0x04C11DB7)
//              Processes up to 4 DWORDs (128 bits) per clock cycle with DWORD
//              enables, generating inverted CRC and magic residue verification (0xC704DD7B).
// =============================================================================

`timescale 1ns / 1ps

module pcie_lcrc32_engine
  import pcie_types_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,

  // Control Signals
  input  logic         init_i,           // Initializes CRC to 32'hFFFFFFFF
  input  logic         calc_en_i,        // Accumulate CRC on enabled DWORDs
  input  logic [3:0]   dw_en_i,          // Active DWORD mask [3:0]
  input  logic [127:0] data_i,           // Input data payload (up to 4 DWORDs)

  // Status & Calculated Values
  output logic [31:0]  crc_cur_o,        // Current internal register state
  output logic [31:0]  crc_inv_o,        // Inverted CRC (crc_cur ^ 32'hFFFFFFFF)
  output logic [31:0]  crc_transmitted_o,// Formatted as PCIe on-the-wire LCRC
  output logic         residue_match_o   // True if internal state equals 32'hC704DD7B
);

  // ---------------------------------------------------------------------------
  // CRC-32 Single Byte Computation Function
  // Shifts bit 0 first (PCIe transmission order)
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] crc32_byte (
    input logic [31:0] c_in,
    input logic [7:0]  b_in
  );
    logic [31:0] c;
    logic        fb;

    c = c_in;
    for (int i = 0; i < 8; i++) begin
      fb = c[31] ^ b_in[i];
      c  = {c[30:0], 1'b0} ^ (fb ? LCRC32_POLY : 32'h0);
    end
    return c;
  endfunction

  // ---------------------------------------------------------------------------
  // CRC-32 Single DWORD (32-bit) Computation Function
  // Byte 0 (bits 7:0) is processed first, followed by Byte 1, 2, 3
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] crc32_dword (
    input logic [31:0] c_in,
    input logic [31:0] dw_in
  );
    logic [31:0] c;
    c = crc32_byte(c_in, dw_in[7:0]);
    c = crc32_byte(c,    dw_in[15:8]);
    c = crc32_byte(c,    dw_in[23:16]);
    c = crc32_byte(c,    dw_in[31:24]);
    return c;
  endfunction

  // ---------------------------------------------------------------------------
  // Combinational CRC Next State Computation across 1-4 DWORDs
  // ---------------------------------------------------------------------------
  logic [31:0] crc_state_q, crc_state_d;
  logic [31:0] next_c0, next_c1, next_c2, next_c3;

  always_comb begin
    if (init_i) begin
      crc_state_d = LCRC32_INIT;
    end else if (calc_en_i) begin
      // Step through DWORD 0
      next_c0 = dw_en_i[0] ? crc32_dword(crc_state_q, data_i[31:0])   : crc_state_q;
      // Step through DWORD 1
      next_c1 = dw_en_i[1] ? crc32_dword(next_c0,     data_i[63:32])  : next_c0;
      // Step through DWORD 2
      next_c2 = dw_en_i[2] ? crc32_dword(next_c1,     data_i[95:64])  : next_c1;
      // Step through DWORD 3
      next_c3 = dw_en_i[3] ? crc32_dword(next_c2,     data_i[127:96]) : next_c2;

      crc_state_d = next_c3;
    end else begin
      crc_state_d = crc_state_q;
    end
  end

  // ---------------------------------------------------------------------------
  // Sequential Register Update
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_state_q <= LCRC32_INIT;
    end else begin
      crc_state_q <= crc_state_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Output Generation & PCIe Wire Format Mapping
  // PCIe specification: inverted register is mapped with bit reflection per byte
  // ---------------------------------------------------------------------------
  assign crc_cur_o       = crc_state_q;
  assign crc_inv_o       = crc_state_q ^ LCRC32_XOR_OUT;
  assign residue_match_o = (crc_state_q == LCRC32_RESIDUE);

  // Wire format: bit-reversal of each byte of crc_inv_o
  // Byte 3 = bits 31:24, Byte 2 = bits 23:16, Byte 1 = bits 15:8, Byte 0 = bits 7:0
  genvar b, bit_idx;
  generate
    for (b = 0; b < 4; b++) begin : gen_wire_bytes
      for (bit_idx = 0; bit_idx < 8; bit_idx++) begin : gen_wire_bits
        assign crc_transmitted_o[b*8 + bit_idx] = crc_inv_o[b*8 + (7 - bit_idx)];
      end
    end
  endgenerate

endmodule : pcie_lcrc32_engine
