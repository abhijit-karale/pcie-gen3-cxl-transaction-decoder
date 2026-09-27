// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_tlp_parser
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: TLP framing boundary identifier, STP token decoder, DWORD-aligned
//              packet accumulator, and integrated 32-bit LCRC verification engine.
//              Emits decoded TLP packets over a streaming AXI-Stream-like interface.
// =============================================================================

`timescale 1ns / 1ps

module pcie_tlp_parser
  import pcie_types_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,

  // Stream Input from Elastic Buffer (sys_clk domain)
  input  logic         buf_valid_i,
  input  logic [1:0]   buf_sync_hdr_i,
  input  logic [127:0] buf_data_i,
  input  logic         buf_is_data_i,
  input  logic         buf_is_os_i,
  output logic         buf_ready_o,

  // Decoded TLP Egress Streaming Interface
  output logic         tlp_valid_o,
  output logic         tlp_start_o,
  output logic         tlp_end_o,
  output logic [127:0] tlp_data_o,
  output logic [3:0]   tlp_keep_o,
  output logic [11:0]  tlp_seq_num_o,
  output logic [9:0]   tlp_length_dw_o,
  output logic [127:0] tlp_header_o,
  output logic         tlp_is_4dw_o,
  output logic         tlp_error_o,
  output logic         tlp_lcrc_err_o,
  output logic         tlp_stp_err_o,

  // Diagnostics & Telemetry
  output logic [31:0]  tlp_success_cnt_o,
  output logic [31:0]  tlp_error_cnt_o
);

  assign buf_ready_o = 1'b1; // Parser can continuously accept incoming blocks

  // ---------------------------------------------------------------------------
  // DWORD Slicing
  // ---------------------------------------------------------------------------
  logic [31:0] in_dw [0:3];
  assign in_dw[0] = buf_data_i[31:0];
  assign in_dw[1] = buf_data_i[63:32];
  assign in_dw[2] = buf_data_i[95:64];
  assign in_dw[3] = buf_data_i[127:96];

  // ---------------------------------------------------------------------------
  // STP Token Scanner Function
  // Checks for Byte 0 == 8'hF0 in any of the 4 DWORDs
  // ---------------------------------------------------------------------------
  function automatic logic is_stp(input logic [31:0] dw);
    return (dw[7:0] == TOKEN_STP);
  endfunction

  function automatic logic [11:0] extract_seq_num(input logic [31:0] dw);
    return {dw[13:8], dw[23:18]};
  endfunction

  function automatic logic [9:0] extract_length(input logic [31:0] dw);
    return {dw[15:14], dw[31:24]};
  endfunction

  function automatic logic check_parity(input logic [31:0] dw);
    // Even parity across the 32-bit token
    return ^dw;
  endfunction

  // ---------------------------------------------------------------------------
  // Parser FSM States
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    PARSE_IDLE     = 3'b000,
    PARSE_HEADER   = 3'b001,
    PARSE_PAYLOAD  = 3'b010,
    PARSE_LCRC     = 3'b011,
    PARSE_END      = 3'b100
  } parse_state_e;

  parse_state_e state_q, state_d;

  // ---------------------------------------------------------------------------
  // Packet Tracking Registers
  // ---------------------------------------------------------------------------
  logic [11:0]  seq_num_q,     seq_num_d;
  logic [9:0]   length_dw_q,   length_dw_d;
  logic [9:0]   payload_cnt_q, payload_cnt_d;
  logic [127:0] header_q,      header_d;
  logic [1:0]   header_dw_cnt_q, header_dw_cnt_d;
  logic         is_4dw_q,      is_4dw_d;
  logic         stp_err_q,     stp_err_d;
  logic         lcrc_err_q,    lcrc_err_d;
  logic         poisoned_q,    poisoned_d;

  // LCRC Engine Control Signals
  logic         lcrc_init;
  logic         lcrc_calc_en;
  logic [3:0]   lcrc_dw_en;
  logic [127:0] lcrc_data_in;
  logic [31:0]  lcrc_cur;
  logic [31:0]  lcrc_inv;
  logic [31:0]  lcrc_transmitted;
  logic         lcrc_residue_match;

  // Instantiate 32-bit LCRC Engine
  pcie_lcrc32_engine u_lcrc32 (
    .clk               (clk),
    .rst_n             (rst_n),
    .init_i            (lcrc_init),
    .calc_en_i         (lcrc_calc_en),
    .dw_en_i           (lcrc_dw_en),
    .data_i            (lcrc_data_in),
    .crc_cur_o         (lcrc_cur),
    .crc_inv_o         (lcrc_inv),
    .crc_transmitted_o (lcrc_transmitted),
    .residue_match_o   (lcrc_residue_match)
  );

  // ---------------------------------------------------------------------------
  // Parser FSM Combinational Logic
  // ---------------------------------------------------------------------------
  always_comb begin
    state_d         = state_q;
    seq_num_d       = seq_num_q;
    length_dw_d     = length_dw_q;
    payload_cnt_d   = payload_cnt_q;
    header_d        = header_q;
    header_dw_cnt_d = header_dw_cnt_q;
    is_4dw_d        = is_4dw_q;
    stp_err_d       = stp_err_q;
    lcrc_err_d      = lcrc_err_q;
    poisoned_d      = poisoned_q;

    // LCRC defaults
    lcrc_init       = 1'b0;
    lcrc_calc_en    = 1'b0;
    lcrc_dw_en      = 4'b0000;
    lcrc_data_in    = buf_data_i;

    case (state_q)
      PARSE_IDLE: begin
        if (buf_valid_i && buf_is_data_i) begin
          // Scan for STP token starting at DW 0
          if (is_stp(in_dw[0])) begin
            lcrc_init       = 1'b1; // Initialize CRC engine
            seq_num_d       = extract_seq_num(in_dw[0]);
            length_dw_d     = extract_length(in_dw[0]);
            stp_err_d       = check_parity(in_dw[0]); // Check parity bit
            payload_cnt_d   = '0;
            lcrc_err_d      = 1'b0;
            poisoned_d      = 1'b0;

            // DW1 is first DWORD of Header
            header_d[31:0]  = in_dw[1];
            // Format bits [31:29] in first header DWORD: bit 29 indicates 4DW
            is_4dw_d        = in_dw[1][29];
            header_d[63:32] = in_dw[2];
            header_d[95:64] = in_dw[3];
            header_dw_cnt_d = 2'd3; // 3 DWORDs collected

            // Accumulate Header into CRC
            lcrc_calc_en    = 1'b1;
            lcrc_dw_en      = 4'b1110; // DW1, DW2, DW3

            if (in_dw[1][29]) begin
              // Needs 4DW header -> 1 more DW needed
              state_d = PARSE_HEADER;
            end else if (length_dw_d > 0) begin
              state_d = PARSE_PAYLOAD;
            end else begin
              state_d = PARSE_LCRC;
            end
          end
        end
      end

      PARSE_HEADER: begin
        if (buf_valid_i && buf_is_data_i) begin
          // 4th DWORD of Header is in DW0
          header_d[127:96] = in_dw[0];
          lcrc_calc_en     = 1'b1;
          lcrc_dw_en       = 4'b0001; // DW0

          if (length_dw_q > 0) begin
            // DW1, DW2, DW3 are payload
            payload_cnt_d = payload_cnt_q + 10'd3;
            lcrc_dw_en    = 4'b1111;
            if (payload_cnt_d >= length_dw_q) begin
              state_d = PARSE_LCRC;
            end else begin
              state_d = PARSE_PAYLOAD;
            end
          end else begin
            // Check LCRC next
            state_d = PARSE_LCRC;
          end
        end
      end

      PARSE_PAYLOAD: begin
        if (buf_valid_i && buf_is_data_i) begin
          lcrc_calc_en = 1'b1;
          if (payload_cnt_q + 10'd4 < length_dw_q) begin
            payload_cnt_d = payload_cnt_q + 10'd4;
            lcrc_dw_en    = 4'b1111;
          end else begin
            // Final payload DWORDs
            payload_cnt_d = length_dw_q;
            lcrc_dw_en    = 4'b1111;
            state_d       = PARSE_LCRC;
          end
        end
      end

      PARSE_LCRC: begin
        if (buf_valid_i && buf_is_data_i) begin
          // Verify received LCRC DWORD against calculated LCRC
          // Check DW0 for LCRC
          if (in_dw[0] != lcrc_transmitted && !lcrc_residue_match) begin
            lcrc_err_d = 1'b1;
          end else begin
            lcrc_err_d = 1'b0;
          end

          // Check if poisoned (EDB token in DW1)
          if (in_dw[1][7:0] == TOKEN_EDB) begin
            poisoned_d = 1'b1;
          end

          state_d = PARSE_END;
        end
      end

      PARSE_END: begin
        state_d = PARSE_IDLE;
      end

      default: state_d = PARSE_IDLE;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Synchronous State Register & Output Pipeline
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= PARSE_IDLE;
      seq_num_q         <= '0;
      length_dw_q       <= '0;
      payload_cnt_q     <= '0;
      header_q          <= '0;
      header_dw_cnt_q   <= '0;
      is_4dw_q          <= 1'b0;
      stp_err_q         <= 1'b0;
      lcrc_err_q        <= 1'b0;
      poisoned_q        <= 1'b0;

      tlp_valid_o       <= 1'b0;
      tlp_start_o       <= 1'b0;
      tlp_end_o         <= 1'b0;
      tlp_data_o        <= '0;
      tlp_keep_o        <= '0;
      tlp_seq_num_o     <= '0;
      tlp_length_dw_o   <= '0;
      tlp_header_o      <= '0;
      tlp_is_4dw_o      <= 1'b0;
      tlp_error_o       <= 1'b0;
      tlp_lcrc_err_o    <= 1'b0;
      tlp_stp_err_o     <= 1'b0;

      tlp_success_cnt_o <= '0;
      tlp_error_cnt_o   <= '0;
    end else begin
      state_q         <= state_d;
      seq_num_q       <= seq_num_d;
      length_dw_q     <= length_dw_d;
      payload_cnt_q   <= payload_cnt_d;
      header_q        <= header_d;
      header_dw_cnt_q <= header_dw_cnt_d;
      is_4dw_q        <= is_4dw_d;
      stp_err_q       <= stp_err_d;
      lcrc_err_q      <= lcrc_err_d;
      poisoned_q      <= poisoned_d;

      // Pipeline Output Signals
      if (state_q == PARSE_IDLE && state_d != PARSE_IDLE) begin
        tlp_start_o     <= 1'b1;
        tlp_valid_o     <= 1'b1;
        tlp_end_o       <= 1'b0;
        tlp_seq_num_o   <= seq_num_d;
        tlp_length_dw_o <= length_dw_d;
        tlp_header_o    <= header_d;
        tlp_is_4dw_o    <= is_4dw_d;
        tlp_data_o      <= buf_data_i;
        tlp_keep_o      <= 4'b1110;
        tlp_error_o     <= 1'b0;
        tlp_lcrc_err_o  <= 1'b0;
        tlp_stp_err_o   <= stp_err_d;
      end else if (state_q == PARSE_PAYLOAD || state_q == PARSE_HEADER) begin
        tlp_start_o     <= 1'b0;
        tlp_valid_o     <= 1'b1;
        tlp_end_o       <= 1'b0;
        tlp_data_o      <= buf_data_i;
        tlp_keep_o      <= 4'b1111;
      end else if (state_q == PARSE_END) begin
        tlp_start_o     <= 1'b0;
        tlp_valid_o     <= 1'b1;
        tlp_end_o       <= 1'b1;
        tlp_data_o      <= buf_data_i;
        tlp_keep_o      <= 4'b0001;
        tlp_error_o     <= lcrc_err_q | stp_err_q | poisoned_q;
        tlp_lcrc_err_o  <= lcrc_err_q;
        tlp_stp_err_o   <= stp_err_q;

        // Telemetry Update
        if (lcrc_err_q | stp_err_q | poisoned_q) begin
          tlp_error_cnt_o <= tlp_error_cnt_o + 1'b1;
        end else begin
          tlp_success_cnt_o <= tlp_success_cnt_o + 1'b1;
        end
      end else begin
        tlp_start_o    <= 1'b0;
        tlp_valid_o    <= 1'b0;
        tlp_end_o      <= 1'b0;
        tlp_data_o     <= '0;
        tlp_keep_o     <= '0;
        tlp_error_o    <= 1'b0;
        tlp_lcrc_err_o <= 1'b0;
        tlp_stp_err_o  <= 1'b0;
      end
    end
  end

endmodule : pcie_tlp_parser
