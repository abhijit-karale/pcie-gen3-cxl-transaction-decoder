// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_sync_header_aligner
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: 128b/130b Sync Header decoder, block lock acquisition FSM,
//              and 100% corrupted sync header detection engine.
// =============================================================================

`timescale 1ns / 1ps

module pcie_sync_header_aligner
  import pcie_types_pkg::*;
(
  input  logic         clk,
  input  logic         rst_n,

  // Raw Physical Interface Inputs (from CDR / Gearbox)
  input  logic         rx_valid_i,
  input  logic [1:0]   rx_sync_hdr_i,
  input  logic [127:0] rx_data_i,

  // Aligned Egress Interface to Descrambler
  output logic         aligner_valid_o,
  output logic [1:0]   aligner_sync_hdr_o,
  output logic [127:0] aligner_data_o,
  output logic         aligner_is_data_o,
  output logic         aligner_is_os_o,

  // Status & Telemetry Diagnostics
  output logic         sync_header_err_o,
  output logic         block_lock_o,
  output logic         link_recovery_req_o,
  output logic [31:0]  corrupt_hdr_cnt_o,
  output logic [31:0]  valid_block_cnt_o
);

  // ---------------------------------------------------------------------------
  // FSM State Definitions
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    STATE_HUNT      = 2'b00,
    STATE_PRE_LOCK  = 2'b01,
    STATE_LOCKED    = 2'b10,
    STATE_RECOVERY  = 2'b11
  } lock_state_e;

  lock_state_e state_q, state_d;

  // ---------------------------------------------------------------------------
  // Internal Signals & Counters
  // ---------------------------------------------------------------------------
  logic [3:0]  consec_valid_q, consec_valid_d;
  logic [2:0]  consec_err_q,   consec_err_d;

  logic        is_valid_header;
  logic        is_corrupt_header;
  logic        is_data_block;
  logic        is_os_block;

  // ---------------------------------------------------------------------------
  // Header Combinational Classification
  // ---------------------------------------------------------------------------
  always_comb begin
    is_valid_header   = 1'b0;
    is_corrupt_header = 1'b0;
    is_data_block     = 1'b0;
    is_os_block       = 1'b0;

    if (rx_valid_i) begin
      case (rx_sync_hdr_i)
        SYNC_HDR_DATA: begin
          is_valid_header = 1'b1;
          is_data_block   = 1'b1;
        end
        SYNC_HDR_ORDERED_SET: begin
          is_valid_header = 1'b1;
          is_os_block     = 1'b1;
        end
        SYNC_HDR_ERR_00,
        SYNC_HDR_ERR_11: begin
          is_corrupt_header = 1'b1;
        end
        default: begin
          is_corrupt_header = 1'b1;
        end
      endcase
    end
  end

  // Error output pulse on ANY corrupted header when rx_valid_i is asserted
  assign sync_header_err_o = rx_valid_i & is_corrupt_header;

  // ---------------------------------------------------------------------------
  // Block Lock FSM Next-State Logic
  // ---------------------------------------------------------------------------
  always_comb begin
    state_d             = state_q;
    consec_valid_d      = consec_valid_q;
    consec_err_d        = consec_err_q;
    link_recovery_req_o = 1'b0;

    if (rx_valid_i) begin
      case (state_q)
        STATE_HUNT: begin
          consec_err_d = '0;
          if (is_valid_header) begin
            consec_valid_d = consec_valid_q + 1'b1;
            if (consec_valid_q >= 4'd3) begin
              state_d        = STATE_PRE_LOCK;
              consec_valid_d = '0;
            end
          end else begin
            consec_valid_d = '0;
          end
        end

        STATE_PRE_LOCK: begin
          consec_err_d = '0;
          if (is_valid_header) begin
            consec_valid_d = consec_valid_q + 1'b1;
            if (consec_valid_q >= 4'd7) begin
              state_d        = STATE_LOCKED;
              consec_valid_d = '0;
            end
          end else begin
            // Single error during pre-lock returns to HUNT
            state_d        = STATE_HUNT;
            consec_valid_d = '0;
          end
        end

        STATE_LOCKED: begin
          consec_valid_d = '0;
          if (is_corrupt_header) begin
            consec_err_d = consec_err_q + 1'b1;
            // 4 consecutive corrupted sync headers triggers Link Recovery
            if (consec_err_q >= 3'd3) begin
              state_d             = STATE_RECOVERY;
              link_recovery_req_o = 1'b1;
              consec_err_d        = '0;
            end
          end else begin
            // Error count resets upon a valid header
            consec_err_d = '0;
          end
        end

        STATE_RECOVERY: begin
          link_recovery_req_o = 1'b1;
          consec_valid_d      = '0;
          consec_err_d        = '0;
          state_d             = STATE_HUNT;
        end

        default: state_d = STATE_HUNT;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Synchronous State & Telemetry Updates
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= STATE_HUNT;
      consec_valid_q    <= '0;
      consec_err_q      <= '0;
      corrupt_hdr_cnt_o <= '0;
      valid_block_cnt_o <= '0;
    end else begin
      state_q        <= state_d;
      consec_valid_q <= consec_valid_d;
      consec_err_q   <= consec_err_d;

      // Telemetry Counters
      if (rx_valid_i) begin
        if (is_corrupt_header) begin
          corrupt_hdr_cnt_o <= corrupt_hdr_cnt_o + 1'b1;
        end else if (is_valid_header) begin
          valid_block_cnt_o <= valid_block_cnt_o + 1'b1;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Pipeline Register Output Stage
  // ---------------------------------------------------------------------------
  assign block_lock_o = (state_q == STATE_LOCKED);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aligner_valid_o    <= 1'b0;
      aligner_sync_hdr_o <= 2'b00;
      aligner_data_o     <= '0;
      aligner_is_data_o  <= 1'b0;
      aligner_is_os_o    <= 1'b0;
    end else begin
      // Block is forwarded only when locked and header is completely valid
      if (rx_valid_i && (state_q == STATE_LOCKED) && is_valid_header) begin
        aligner_valid_o    <= 1'b1;
        aligner_sync_hdr_o <= rx_sync_hdr_i;
        aligner_data_o     <= rx_data_i;
        aligner_is_data_o  <= is_data_block;
        aligner_is_os_o    <= is_os_block;
      end else begin
        aligner_valid_o    <= 1'b0;
        aligner_sync_hdr_o <= 2'b00;
        aligner_data_o     <= '0;
        aligner_is_data_o  <= 1'b0;
        aligner_is_os_o    <= 1'b0;
      end
    end
  end

endmodule : pcie_sync_header_aligner
