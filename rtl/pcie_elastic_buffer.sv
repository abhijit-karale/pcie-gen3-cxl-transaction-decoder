// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_elastic_buffer
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: Dual-Clock Asynchronous FIFO Elastic Buffer compensating for
//              +/- 300 ppm clock drift. Implements 3-stage MTBF Gray pointer CDC,
//              inversion-free pointer safety, and automatic SKP Ordered Set
//              insertion/deletion based on high/low occupancy watermarks.
// =============================================================================

`timescale 1ns / 1ps

module pcie_elastic_buffer
  import pcie_types_pkg::*;
#(
  parameter int unsigned DEPTH          = FIFO_DEPTH,     // 32 entries
  parameter int unsigned HIGH_WM        = HIGH_WATERMARK, // 24 entries
  parameter int unsigned LOW_WM         = LOW_WATERMARK,  // 8 entries
  parameter int unsigned ADDR_W         = $clog2(DEPTH)   // 5 bits
)(
  // ---------------------------------------------------------------------------
  // Write Domain (Recovered Clock: rx_pclk @ 250 MHz +/- 300 ppm)
  // ---------------------------------------------------------------------------
  input  logic              wr_clk,
  input  logic              wr_rst_n,

  input  logic              wr_valid_i,
  input  logic [1:0]        wr_sync_hdr_i,
  input  logic [127:0]      wr_data_i,
  input  logic              wr_is_data_i,
  input  logic              wr_is_os_i,
  input  logic              wr_is_skp_i,

  output logic              fifo_full_o,
  output logic              fifo_overflow_err_o,
  output logic [ADDR_W:0]   wr_occupancy_o,
  output logic [31:0]       skp_deleted_cnt_o,

  // ---------------------------------------------------------------------------
  // Read Domain (System Core Clock: sys_clk @ 250 MHz Nominal)
  // ---------------------------------------------------------------------------
  input  logic              rd_clk,
  input  logic              rd_rst_n,

  input  logic              rd_ready_i,
  output logic              rd_valid_o,
  output logic [1:0]        rd_sync_hdr_o,
  output logic [127:0]      rd_data_o,
  output logic              rd_is_data_o,
  output logic              rd_is_os_o,
  output logic              rd_is_skp_o,

  output logic              fifo_empty_o,
  output logic              fifo_underflow_err_o,
  output logic [ADDR_W:0]   rd_occupancy_o,
  output logic [31:0]       skp_inserted_cnt_o
);

  // ---------------------------------------------------------------------------
  // FIFO Payload Width & Structure
  // Payload: Data (128) + Sync Header (2) + is_data (1) + is_os (1) + is_skp (1) = 133 bits
  // ---------------------------------------------------------------------------
  localparam int unsigned PAYLOAD_W = 128 + 2 + 1 + 1 + 1;
  typedef struct packed {
    logic [1:0]   sync_hdr;
    logic         is_data;
    logic         is_os;
    logic         is_skp;
    logic [127:0] data;
  } fifo_entry_t;

  // Dual-Port RAM Memory Array
  fifo_entry_t mem [0:DEPTH-1];
  fifo_entry_t wr_entry;
  fifo_entry_t rd_entry;

  assign wr_entry = '{
    sync_hdr: wr_sync_hdr_i,
    is_data : wr_is_data_i,
    is_os   : wr_is_os_i,
    is_skp  : wr_is_skp_i,
    data    : wr_data_i
  };

  // ---------------------------------------------------------------------------
  // Binary & Gray Pointer Declarations (Width: ADDR_W + 1 = 6 bits)
  // ---------------------------------------------------------------------------
  logic [ADDR_W:0] wr_ptr_bin_q, wr_ptr_bin_d;
  logic [ADDR_W:0] wr_ptr_gray_q, wr_ptr_gray_d;
  logic [ADDR_W:0] rd_ptr_bin_q, rd_ptr_bin_d;
  logic [ADDR_W:0] rd_ptr_gray_q, rd_ptr_gray_d;

  // Synchronizer Flops with ASYNC_REG Attributes
  (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) logic [ADDR_W:0] rd_ptr_gray_sync_wr1, rd_ptr_gray_sync_wr2, rd_ptr_gray_sync_wr3;
  (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) logic [ADDR_W:0] wr_ptr_gray_sync_rd1, wr_ptr_gray_sync_rd2, wr_ptr_gray_sync_rd3;

  logic [ADDR_W:0] rd_ptr_bin_synced_wr;
  logic [ADDR_W:0] wr_ptr_bin_synced_rd;

  // ---------------------------------------------------------------------------
  // Helper Functions: Binary <-> Gray Conversion
  // ---------------------------------------------------------------------------
  function automatic logic [ADDR_W:0] bin2gray(input logic [ADDR_W:0] b);
    return b ^ (b >> 1);
  endfunction

  function automatic logic [ADDR_W:0] gray2bin(input logic [ADDR_W:0] g);
    logic [ADDR_W:0] b;
    b[ADDR_W] = g[ADDR_W];
    for (int i = ADDR_W - 1; i >= 0; i--) begin
      b[i] = b[i+1] ^ g[i];
    end
    return b;
  endfunction

  // ---------------------------------------------------------------------------
  // Multi-Flop CDC Synchronizers (3-Stage for High MTBF at 250 MHz)
  // ---------------------------------------------------------------------------
  // Synchronize rd_ptr_gray into wr_clk domain
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      rd_ptr_gray_sync_wr1 <= '0;
      rd_ptr_gray_sync_wr2 <= '0;
      rd_ptr_gray_sync_wr3 <= '0;
    end else begin
      rd_ptr_gray_sync_wr1 <= rd_ptr_gray_q;
      rd_ptr_gray_sync_wr2 <= rd_ptr_gray_sync_wr1;
      rd_ptr_gray_sync_wr3 <= rd_ptr_gray_sync_wr2;
    end
  end
  assign rd_ptr_bin_synced_wr = gray2bin(rd_ptr_gray_sync_wr3);

  // Synchronize wr_ptr_gray into rd_clk domain
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      wr_ptr_gray_sync_rd1 <= '0;
      wr_ptr_gray_sync_rd2 <= '0;
      wr_ptr_gray_sync_rd3 <= '0;
    end else begin
      wr_ptr_gray_sync_rd1 <= wr_ptr_gray_q;
      wr_ptr_gray_sync_rd2 <= wr_ptr_gray_sync_rd1;
      wr_ptr_gray_sync_rd3 <= wr_ptr_gray_sync_rd2;
    end
  end
  assign wr_ptr_bin_synced_rd = gray2bin(wr_ptr_gray_sync_rd3);

  // ---------------------------------------------------------------------------
  // Occupancy Tracking (Inversion-Safe Modulo Arithmetic)
  // ---------------------------------------------------------------------------
  logic [ADDR_W:0] wr_occupancy;
  logic [ADDR_W:0] rd_occupancy;

  assign wr_occupancy   = wr_ptr_bin_q - rd_ptr_bin_synced_wr;
  assign rd_occupancy   = wr_ptr_bin_synced_rd - rd_ptr_bin_q;
  assign wr_occupancy_o = wr_occupancy;
  assign rd_occupancy_o = rd_occupancy;

  // ---------------------------------------------------------------------------
  // Write Logic & SKP Deletion Engine (+300 ppm Compensation)
  // ---------------------------------------------------------------------------
  logic drop_skp_condition;
  logic wr_fifo_en;

  // Drop SKP when occupancy exceeds High Watermark and incoming block is SKP OS
  assign drop_skp_condition = wr_valid_i && wr_is_skp_i && (wr_occupancy >= HIGH_WM);

  // Full condition: pointers match in lower bits but differ in top bit
  assign fifo_full_o = (wr_ptr_gray_q == {~rd_ptr_gray_sync_wr3[ADDR_W:ADDR_W-1],
                                           rd_ptr_gray_sync_wr3[ADDR_W-2:0]});

  // Write enable to FIFO array: must be valid, not full, and NOT dropped
  assign wr_fifo_en = wr_valid_i & (~fifo_full_o) & (~drop_skp_condition);

  always_comb begin
    wr_ptr_bin_d  = wr_ptr_bin_q;
    if (wr_fifo_en) begin
      wr_ptr_bin_d = wr_ptr_bin_q + 1'b1;
    end
    wr_ptr_gray_d = bin2gray(wr_ptr_bin_d);
  end

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_ptr_bin_q        <= '0;
      wr_ptr_gray_q       <= '0;
      fifo_overflow_err_o <= 1'b0;
      skp_deleted_cnt_o   <= '0;
    end else begin
      wr_ptr_bin_q  <= wr_ptr_bin_d;
      wr_ptr_gray_q <= wr_ptr_gray_d;

      // RAM Write
      if (wr_fifo_en) begin
        mem[wr_ptr_bin_q[ADDR_W-1:0]] <= wr_entry;
      end

      // Overflow Error Flag
      if (wr_valid_i && fifo_full_o && !drop_skp_condition) begin
        fifo_overflow_err_o <= 1'b1;
      end

      // SKP Dropped Telemetry
      if (drop_skp_condition) begin
        skp_deleted_cnt_o <= skp_deleted_cnt_o + 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Read Logic & SKP Insertion Engine (-300 ppm Compensation)
  // ---------------------------------------------------------------------------
  logic duplicate_skp_condition;
  logic rd_fifo_en;
  logic fifo_empty;
  logic [ADDR_W-1:0] rd_addr;

  assign fifo_empty   = (rd_ptr_gray_q == wr_ptr_gray_sync_rd3);
  assign fifo_empty_o = fifo_empty;
  assign rd_addr      = rd_ptr_bin_q[ADDR_W-1:0];

  // Look ahead at RAM output
  assign rd_entry     = mem[rd_addr];

  // If occupancy < LOW_WM and currently reading a SKP OS, duplicate it for 1 cycle
  // by withholding the read pointer increment once
  logic skp_duplicated_q;

  assign duplicate_skp_condition = (!fifo_empty) && rd_entry.is_skp &&
                                   (rd_occupancy <= LOW_WM) && (!skp_duplicated_q);

  // Read pointer advances if ready, not empty, and not duplicating
  assign rd_fifo_en = rd_ready_i && (!fifo_empty) && (!duplicate_skp_condition);

  always_comb begin
    rd_ptr_bin_d  = rd_ptr_bin_q;
    if (rd_fifo_en) begin
      rd_ptr_bin_d = rd_ptr_bin_q + 1'b1;
    end
    rd_ptr_gray_d = bin2gray(rd_ptr_bin_d);
  end

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_ptr_bin_q          <= '0;
      rd_ptr_gray_q         <= '0;
      rd_valid_o            <= 1'b0;
      rd_sync_hdr_o         <= 2'b00;
      rd_data_o             <= '0;
      rd_is_data_o          <= 1'b0;
      rd_is_os_o            <= 1'b0;
      rd_is_skp_o           <= 1'b0;
      fifo_underflow_err_o  <= 1'b0;
      skp_inserted_cnt_o    <= '0;
      skp_duplicated_q      <= 1'b0;
    end else begin
      rd_ptr_bin_q  <= rd_ptr_bin_d;
      rd_ptr_gray_q <= rd_ptr_gray_d;

      // Track duplicate state to ensure we only duplicate once per SKP block
      if (duplicate_skp_condition) begin
        skp_duplicated_q   <= 1'b1;
        skp_inserted_cnt_o <= skp_inserted_cnt_o + 1'b1;
      end else if (rd_fifo_en) begin
        skp_duplicated_q   <= 1'b0;
      end

      // Read Output Registers
      if (rd_ready_i) begin
        if (!fifo_empty) begin
          rd_valid_o    <= 1'b1;
          rd_sync_hdr_o <= rd_entry.sync_hdr;
          rd_data_o     <= rd_entry.data;
          rd_is_data_o  <= rd_entry.is_data;
          rd_is_os_o    <= rd_entry.is_os;
          rd_is_skp_o   <= rd_entry.is_skp;
        end else begin
          rd_valid_o    <= 1'b0;
          rd_sync_hdr_o <= 2'b00;
          rd_data_o     <= '0;
          rd_is_data_o  <= 1'b0;
          rd_is_os_o    <= 1'b0;
          rd_is_skp_o   <= 1'b0;
        end
      end

      // Underflow Flag
      if (rd_ready_i && fifo_empty) begin
        fifo_underflow_err_o <= 1'b1;
      end
    end
  end

endmodule : pcie_elastic_buffer
