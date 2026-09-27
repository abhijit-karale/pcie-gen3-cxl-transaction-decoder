// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_types_pkg
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
// Description: Protocol constants, data structures, polynomials, and enums for
//              128b/130b block framing, descrambling, CDC elastic buffer, and
//              TLP/LCRC processing.
// =============================================================================

`ifndef PCIE_TYPES_PKG_SV
`define PCIE_TYPES_PKG_SV

package pcie_types_pkg;

  // ---------------------------------------------------------------------------
  // 128b/130b Sync Header Encodings
  // ---------------------------------------------------------------------------
  localparam logic [1:0] SYNC_HDR_DATA       = 2'b01; // Data Block
  localparam logic [1:0] SYNC_HDR_ORDERED_SET= 2'b10; // Ordered Set Block
  localparam logic [1:0] SYNC_HDR_ERR_00     = 2'b00; // Illegal Corrupted Sync Header
  localparam logic [1:0] SYNC_HDR_ERR_11     = 2'b11; // Illegal Corrupted Sync Header

  typedef enum logic [1:0] {
    BLOCK_DATA        = 2'b01,
    BLOCK_ORDERED_SET = 2'b10,
    BLOCK_CORRUPT_00  = 2'b00,
    BLOCK_CORRUPT_11  = 2'b11
  } block_type_e;

  // ---------------------------------------------------------------------------
  // Ordered Set Identifiers (PCIe Gen3 / CXL 2.0)
  // ---------------------------------------------------------------------------
  localparam logic [7:0] OS_SYMBOL_SKP       = 8'hAA; // SKP Symbol
  localparam logic [7:0] OS_SYMBOL_SKP_END   = 8'hE1; // SKP End Symbol
  localparam logic [7:0] OS_SYMBOL_TS1       = 8'h1E; // Training Sequence 1
  localparam logic [7:0] OS_SYMBOL_TS2       = 8'h2D; // Training Sequence 2
  localparam logic [7:0] OS_SYMBOL_EIOS      = 8'h66; // Electrical Idle Ordered Set
  localparam logic [7:0] OS_SYMBOL_FTS       = 8'h55; // Fast Training Sequence

  // 32-bit Match pattern for standard SKP Ordered Set
  localparam logic [31:0] SKP_PATTERN_32     = {4{OS_SYMBOL_SKP}}; // 32'hAAAAAAAA

  // ---------------------------------------------------------------------------
  // Framing Tokens (PCIe Gen3 128b/130b Data Blocks)
  // ---------------------------------------------------------------------------
  localparam logic [7:0] TOKEN_STP           = 8'hF0; // Start of TLP Token
  localparam logic [7:0] TOKEN_SDP           = 8'hAC; // Start of DLLP Token
  localparam logic [7:0] TOKEN_END           = 8'hDF; // End of Packet Token
  localparam logic [7:0] TOKEN_EDB           = 8'h0F; // End Bad Packet Token (Poisoned)
  localparam logic [7:0] TOKEN_PAD           = 8'hF7; // Pad Token

  // ---------------------------------------------------------------------------
  // LFSR Polynomial & Configuration
  // Polynomial: G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
  // ---------------------------------------------------------------------------
  localparam int unsigned LFSR_WIDTH         = 23;
  localparam logic [22:0] LFSR_POLY          = 23'b101000010000000100100101; // Tap mask
  localparam logic [22:0] LFSR_LANE0_SEED    = 23'h1DBFBC; // Standard Gen3 Lane 0 Seed

  // ---------------------------------------------------------------------------
  // 32-bit LCRC Polynomial Configuration
  // Polynomial: x^32 + x^26 + x^23 + x^22 + x^16 + x^12 + x^11 + x^10 +
  //             x^8 + x^7 + x^5 + x^4 + x^2 + x + 1 (0x04C11DB7)
  // ---------------------------------------------------------------------------
  localparam logic [31:0] LCRC32_POLY        = 32'h04C11DB7;
  localparam logic [31:0] LCRC32_INIT        = 32'hFFFFFFFF;
  localparam logic [31:0] LCRC32_XOR_OUT     = 32'hFFFFFFFF;
  localparam logic [31:0] LCRC32_RESIDUE     = 32'hC704DD7B; // Error-free residue

  // ---------------------------------------------------------------------------
  // Elastic Buffer FIFO Sizing & Watermarks
  // ---------------------------------------------------------------------------
  localparam int unsigned FIFO_DEPTH         = 32;
  localparam int unsigned FIFO_ADDR_W        = $clog2(FIFO_DEPTH); // 5 bits
  localparam int unsigned HIGH_WATERMARK     = 24; // Swallows SKP OS above this
  localparam int unsigned LOW_WATERMARK      = 8;  // Duplicates SKP OS below this
  localparam int unsigned NOMINAL_LEVEL      = 16; // Center equilibrium point

  // ---------------------------------------------------------------------------
  // Structure Definitions
  // ---------------------------------------------------------------------------
  // STP Token Decoded Fields
  typedef struct packed {
    logic [11:0] seq_num;    // TLP Sequence Number (12 bits)
    logic [9:0]  length_dw;  // TLP Length in DWORDs (10 bits)
    logic        parity;     // Parity bit
    logic        valid;      // Valid STP token decoded
  } stp_token_t;

  // Decoded TLP Egress Header & Metadata
  typedef struct packed {
    logic [11:0] seq_num;
    logic [9:0]  length_dw;
    logic [127:0]hdr_bytes;  // TLP Header (3 or 4 DWORDs)
    logic        is_4dw_hdr;
    logic        poisoned;
    logic        lcrc_valid;
    logic        error;
  } tlp_meta_t;

endpackage : pcie_types_pkg

`endif // PCIE_TYPES_PKG_SV
