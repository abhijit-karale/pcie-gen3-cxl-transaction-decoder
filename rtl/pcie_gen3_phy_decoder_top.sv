// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_gen3_phy_decoder_top
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: Production-grade top-level integration of the Physical Link Layer
//              Transaction Decoder. Seamlessly connects 128b/130b sync header
//              aligner, 23-bit parallel LFSR descrambler, dual-clock elastic
//              buffer CDC with SKP compensation, and TLP parser with LCRC-32 engine.
// =============================================================================

`timescale 1ns / 1ps

module pcie_gen3_phy_decoder_top
  import pcie_types_pkg::*;
(
  // ---------------------------------------------------------------------------
  // Clock & Reset Interfaces
  // ---------------------------------------------------------------------------
  input  logic         rx_pclk,             // Recovered Clock (250 MHz +/- 300 ppm)
  input  logic         rx_rst_n,            // Active-Low Reset (rx domain)
  input  logic         sys_clk,             // System Core Clock (250 MHz Nominal)
  input  logic         sys_rst_n,           // Active-Low Reset (sys domain)

  // ---------------------------------------------------------------------------
  // Control & Configuration
  // ---------------------------------------------------------------------------
  input  logic         descramble_en_i,     // 1 = Descramble payload, 0 = Bypass
  input  logic         seed_load_i,         // Pulse to load custom LFSR seed
  input  logic [22:0]  seed_val_i,          // Seed value (default: 23'h1DBFBC)

  // ---------------------------------------------------------------------------
  // Physical Receiver Input (from CDR / PIPE Physical Interface)
  // ---------------------------------------------------------------------------
  input  logic         rx_valid_i,          // 128-bit block valid
  input  logic [1:0]   rx_sync_hdr_i,       // 2-bit Sync Header (01=Data, 10=OS)
  input  logic [127:0] rx_data_i,           // 128-bit raw physical block payload

  // ---------------------------------------------------------------------------
  // Decoded TLP Egress Streaming Interface (sys_clk domain)
  // ---------------------------------------------------------------------------
  output logic         tlp_valid_o,         // Valid packet beat
  output logic         tlp_start_o,         // Start of Packet (SOP)
  output logic         tlp_end_o,           // End of Packet (EOP)
  output logic [127:0] tlp_data_o,          // Streaming TLP payload/header
  output logic [3:0]   tlp_keep_o,          // Active DWORD mask
  output logic [11:0]  tlp_seq_num_o,       // 12-bit Sequence Number
  output logic [9:0]   tlp_length_dw_o,     // Packet Length in DWORDs
  output logic [127:0] tlp_header_o,        // Decoded TLP Header
  output logic         tlp_is_4dw_o,        // 1 = 4DW Header, 0 = 3DW Header
  output logic         tlp_error_o,         // Packet corrupted (LCRC/STP/EDB)
  output logic         tlp_lcrc_err_o,      // LCRC verification failed
  output logic         tlp_stp_err_o,       // STP framing/parity error

  // ---------------------------------------------------------------------------
  // Status, Telemetry & Link Integrity Diagnostics
  // ---------------------------------------------------------------------------
  output logic         block_lock_o,        // 128b/130b Block Lock acquired
  output logic         sync_header_err_o,   // Corrupted Sync Header detected (00/11)
  output logic         link_recovery_req_o, // 4 consecutive errors -> Link Recovery
  output logic         fifo_full_o,         // Elastic buffer FIFO full
  output logic         fifo_empty_o,        // Elastic buffer FIFO empty
  output logic         fifo_overflow_err_o, // Elastic buffer overflow error
  output logic         fifo_underflow_err_o,// Elastic buffer underflow error
  output logic [5:0]   wr_occupancy_o,      // Elastic buffer write occupancy
  output logic [5:0]   rd_occupancy_o,      // Elastic buffer read occupancy
  output logic [31:0]  skp_deleted_cnt_o,   // Count of swallowed SKP OS (+300 ppm)
  output logic [31:0]  skp_inserted_cnt_o,  // Count of duplicated SKP OS (-300 ppm)
  output logic [31:0]  corrupt_hdr_cnt_o,   // Total corrupted sync headers detected
  output logic [31:0]  valid_block_cnt_o,   // Total valid 128b/130b blocks received
  output logic [31:0]  tlp_success_cnt_o,   // Total error-free TLPs successfully parsed
  output logic [31:0]  tlp_error_cnt_o      // Total corrupted/errored TLPs
);

  // ---------------------------------------------------------------------------
  // Interconnect Wires: Aligner -> Descrambler (rx_pclk domain)
  // ---------------------------------------------------------------------------
  logic         aligner_valid;
  logic [1:0]   aligner_sync_hdr;
  logic [127:0] aligner_data;
  logic         aligner_is_data;
  logic         aligner_is_os;

  // ---------------------------------------------------------------------------
  // Interconnect Wires: Descrambler -> Elastic Buffer (rx_pclk domain)
  // ---------------------------------------------------------------------------
  logic         descrambler_valid;
  logic [1:0]   descrambler_sync_hdr;
  logic [127:0] descrambler_data;
  logic         descrambler_is_data;
  logic         descrambler_is_os;
  logic         descrambler_is_skp;
  logic [22:0]  lfsr_state;

  // ---------------------------------------------------------------------------
  // Interconnect Wires: Elastic Buffer -> TLP Parser (sys_clk domain)
  // ---------------------------------------------------------------------------
  logic         buf_valid;
  logic [1:0]   buf_sync_hdr;
  logic [127:0] buf_data;
  logic         buf_is_data;
  logic         buf_is_os;
  logic         buf_is_skp;
  logic         buf_ready;

  // ===========================================================================
  // 1. 128b/130b Sync Header Aligner & Corrupted Header Detector
  // ===========================================================================
  pcie_sync_header_aligner u_aligner (
    .clk                 (rx_pclk),
    .rst_n               (rx_rst_n),
    .rx_valid_i          (rx_valid_i),
    .rx_sync_hdr_i       (rx_sync_hdr_i),
    .rx_data_i           (rx_data_i),
    .aligner_valid_o     (aligner_valid),
    .aligner_sync_hdr_o  (aligner_sync_hdr),
    .aligner_data_o      (aligner_data),
    .aligner_is_data_o   (aligner_is_data),
    .aligner_is_os_o     (aligner_is_os),
    .sync_header_err_o   (sync_header_err_o),
    .block_lock_o        (block_lock_o),
    .link_recovery_req_o (link_recovery_req_o),
    .corrupt_hdr_cnt_o   (corrupt_hdr_cnt_o),
    .valid_block_cnt_o   (valid_block_cnt_o)
  );

  // ===========================================================================
  // 2. Parallel 128-bit LFSR Descrambler (x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1)
  // ===========================================================================
  pcie_descrambler_lfsr u_descrambler (
    .clk                    (rx_pclk),
    .rst_n                  (rx_rst_n),
    .descramble_en_i        (descramble_en_i),
    .seed_load_i            (seed_load_i),
    .seed_val_i             (seed_val_i),
    .aligner_valid_i        (aligner_valid),
    .aligner_sync_hdr_i     (aligner_sync_hdr),
    .aligner_data_i         (aligner_data),
    .aligner_is_data_i      (aligner_is_data),
    .aligner_is_os_i        (aligner_is_os),
    .descrambler_valid_o    (descrambler_valid),
    .descrambler_sync_hdr_o (descrambler_sync_hdr),
    .descrambler_data_o     (descrambler_data),
    .descrambler_is_data_o  (descrambler_is_data),
    .descrambler_is_os_o    (descrambler_is_os),
    .descrambler_is_skp_o   (descrambler_is_skp),
    .lfsr_state_o           (lfsr_state)
  );

  // ===========================================================================
  // 3. Elastic Buffer CDC FIFO (+/- 300 ppm Clock Tolerance Compensation)
  // ===========================================================================
  pcie_elastic_buffer #(
    .DEPTH          (FIFO_DEPTH),
    .HIGH_WM        (HIGH_WATERMARK),
    .LOW_WM         (LOW_WATERMARK)
  ) u_elastic_buffer (
    // Write Domain (rx_pclk)
    .wr_clk               (rx_pclk),
    .wr_rst_n             (rx_rst_n),
    .wr_valid_i           (descrambler_valid),
    .wr_sync_hdr_i        (descrambler_sync_hdr),
    .wr_data_i            (descrambler_data),
    .wr_is_data_i         (descrambler_is_data),
    .wr_is_os_i           (descrambler_is_os),
    .wr_is_skp_i          (descrambler_is_skp),
    .fifo_full_o          (fifo_full_o),
    .fifo_overflow_err_o  (fifo_overflow_err_o),
    .wr_occupancy_o       (wr_occupancy_o),
    .skp_deleted_cnt_o    (skp_deleted_cnt_o),

    // Read Domain (sys_clk)
    .rd_clk               (sys_clk),
    .rd_rst_n             (sys_rst_n),
    .rd_ready_i           (buf_ready),
    .rd_valid_o           (buf_valid),
    .rd_sync_hdr_o        (buf_sync_hdr),
    .rd_data_o            (buf_data),
    .rd_is_data_o         (buf_is_data),
    .rd_is_os_o           (buf_is_os),
    .rd_is_skp_o          (buf_is_skp),
    .fifo_empty_o         (fifo_empty_o),
    .fifo_underflow_err_o (fifo_underflow_err_o),
    .rd_occupancy_o       (rd_occupancy_o),
    .skp_inserted_cnt_o   (skp_inserted_cnt_o)
  );

  // ===========================================================================
  // 4. TLP Framing Boundary Parser & Integrated 32-bit LCRC Engine
  // ===========================================================================
  pcie_tlp_parser u_tlp_parser (
    .clk               (sys_clk),
    .rst_n             (sys_rst_n),
    .buf_valid_i       (buf_valid),
    .buf_sync_hdr_i    (buf_sync_hdr),
    .buf_data_i        (buf_data),
    .buf_is_data_i     (buf_is_data),
    .buf_is_os_i       (buf_is_os),
    .buf_ready_o       (buf_ready),
    .tlp_valid_o       (tlp_valid_o),
    .tlp_start_o       (tlp_start_o),
    .tlp_end_o         (tlp_end_o),
    .tlp_data_o        (tlp_data_o),
    .tlp_keep_o        (tlp_keep_o),
    .tlp_seq_num_o     (tlp_seq_num_o),
    .tlp_length_dw_o   (tlp_length_dw_o),
    .tlp_header_o      (tlp_header_o),
    .tlp_is_4dw_o      (tlp_is_4dw_o),
    .tlp_error_o       (tlp_error_o),
    .tlp_lcrc_err_o    (tlp_lcrc_err_o),
    .tlp_stp_err_o     (tlp_stp_err_o),
    .tlp_success_cnt_o (tlp_success_cnt_o),
    .tlp_error_cnt_o   (tlp_error_cnt_o)
  );

endmodule : pcie_gen3_phy_decoder_top
