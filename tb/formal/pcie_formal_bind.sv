// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_formal_bind
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / Formal Verification
// Description: SystemVerilog bind file attaching formal SVA properties to
//              pcie_elastic_buffer, pcie_sync_header_aligner, and pcie_lcrc32_engine.
// =============================================================================

`timescale 1ns / 1ps

module pcie_formal_bind;

  // Bind Elastic Buffer SVA properties
  bind pcie_elastic_buffer elastic_buffer_sva #(
    .DEPTH   (DEPTH),
    .HIGH_WM (HIGH_WM),
    .LOW_WM  (LOW_WM),
    .ADDR_W  (ADDR_W)
  ) u_elastic_buffer_sva (
    .wr_clk                  (wr_clk),
    .wr_rst_n                (wr_rst_n),
    .wr_valid_i              (wr_valid_i),
    .wr_sync_hdr_i           (wr_sync_hdr_i),
    .wr_is_skp_i             (wr_is_skp_i),
    .fifo_full_o             (fifo_full_o),
    .fifo_overflow_err_o     (fifo_overflow_err_o),
    .wr_occupancy_o          (wr_occupancy_o),
    .wr_ptr_bin_q            (wr_ptr_bin_q),
    .wr_ptr_bin_d            (wr_ptr_bin_d),
    .wr_ptr_gray_q           (wr_ptr_gray_q),
    .wr_ptr_gray_d           (wr_ptr_gray_d),
    .wr_fifo_en              (wr_fifo_en),
    .drop_skp_condition      (drop_skp_condition),

    .rd_clk                  (rd_clk),
    .rd_rst_n                (rd_rst_n),
    .rd_ready_i              (rd_ready_i),
    .rd_valid_o              (rd_valid_o),
    .fifo_empty_o            (fifo_empty_o),
    .fifo_underflow_err_o    (fifo_underflow_err_o),
    .rd_occupancy_o          (rd_occupancy_o),
    .rd_ptr_bin_q            (rd_ptr_bin_q),
    .rd_ptr_bin_d            (rd_ptr_bin_d),
    .rd_ptr_gray_q           (rd_ptr_gray_q),
    .rd_ptr_gray_d           (rd_ptr_gray_d),
    .rd_fifo_en              (rd_fifo_en),
    .duplicate_skp_condition (duplicate_skp_condition)
  );

  // Bind Sync Header Aligner SVA properties
  bind pcie_sync_header_aligner sync_header_sva u_sync_header_sva (
    .clk                 (clk),
    .rst_n               (rst_n),
    .rx_valid_i          (rx_valid_i),
    .rx_sync_hdr_i       (rx_sync_hdr_i),
    .sync_header_err_o   (sync_header_err_o),
    .block_lock_o        (block_lock_o),
    .link_recovery_req_o (link_recovery_req_o),
    .corrupt_hdr_cnt_o   (corrupt_hdr_cnt_o),
    .valid_block_cnt_o   (valid_block_cnt_o),
    .state_q             (state_q),
    .consec_err_q        (consec_err_q)
  );

  // Bind LCRC-32 Engine SVA properties
  bind pcie_lcrc32_engine lcrc32_sva u_lcrc32_sva (
    .clk               (clk),
    .rst_n             (rst_n),
    .init_i            (init_i),
    .calc_en_i         (calc_en_i),
    .dw_en_i           (dw_en_i),
    .data_i            (data_i),
    .crc_cur_o         (crc_cur_o),
    .crc_inv_o         (crc_inv_o),
    .crc_transmitted_o (crc_transmitted_o),
    .residue_match_o   (residue_match_o)
  );

endmodule : pcie_formal_bind
