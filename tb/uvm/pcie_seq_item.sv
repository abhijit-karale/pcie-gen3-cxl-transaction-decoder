// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_seq_item
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: Constrained-random UVM transaction item supporting 128b/130b
//              block generation, sync header corruption injection, SKP ordered
//              sets, LCRC corruption, and +/- 300 ppm clock drift parameters.
// =============================================================================

`ifndef PCIE_SEQ_ITEM_SV
`define PCIE_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
import pcie_types_pkg::*;

class pcie_seq_item extends uvm_sequence_item;

  // ---------------------------------------------------------------------------
  // Transaction Fields
  // ---------------------------------------------------------------------------
  rand block_type_e          block_type;
  rand logic [1:0]           sync_hdr;
  rand logic [127:0]         raw_payload;

  // Packet Framing Control
  rand logic                 is_tlp_start;
  rand logic [11:0]          tlp_seq_num;
  rand logic [9:0]           tlp_length_dw;
  rand logic [127:0]         tlp_header;
  rand logic                 is_4dw;
  rand logic                 is_skp_os;

  // Error & Fault Injection Controls
  rand logic                 corrupt_sync_hdr;
  rand logic                 corrupt_lcrc;
  rand logic                 corrupt_stp_parity;

  // Clock Tolerance & Jitter Parameter (-300 to +300 ppm)
  rand int                   clock_drift_ppm;

  // ---------------------------------------------------------------------------
  // UVM Automation Macros
  // ---------------------------------------------------------------------------
  `uvm_object_utils_begin(pcie_seq_item)
    `uvm_field_enum(block_type_e, block_type, UVM_ALL_ON)
    `uvm_field_int(sync_hdr,                  UVM_ALL_ON | UVM_BIN)
    `uvm_field_int(raw_payload,               UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(is_tlp_start,              UVM_ALL_ON)
    `uvm_field_int(tlp_seq_num,               UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(tlp_length_dw,             UVM_ALL_ON | UVM_DEC)
    `uvm_field_int(tlp_header,                UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(is_4dw,                    UVM_ALL_ON)
    `uvm_field_int(is_skp_os,                 UVM_ALL_ON)
    `uvm_field_int(corrupt_sync_hdr,          UVM_ALL_ON)
    `uvm_field_int(corrupt_lcrc,              UVM_ALL_ON)
    `uvm_field_int(corrupt_stp_parity,        UVM_ALL_ON)
    `uvm_field_int(clock_drift_ppm,           UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  // ---------------------------------------------------------------------------
  // Constraints
  // ---------------------------------------------------------------------------
  // Clock drift constraint within PCIe spec (+/- 300 ppm)
  constraint c_clock_drift {
    clock_drift_ppm inside {[-300:300]};
  }

  // Weight distribution: mostly valid data blocks, occasional SKP, rare corruptions
  constraint c_block_distribution {
    block_type dist {
      BLOCK_DATA        := 70,
      BLOCK_ORDERED_SET := 20,
      BLOCK_CORRUPT_00  := 5,
      BLOCK_CORRUPT_11  := 5
    };
  }

  // Sync Header correlation with block type
  constraint c_sync_header_match {
    if (!corrupt_sync_hdr) {
      if (block_type == BLOCK_DATA) {
        sync_hdr == SYNC_HDR_DATA;
      } else if (block_type == BLOCK_ORDERED_SET) {
        sync_hdr == SYNC_HDR_ORDERED_SET;
      } else if (block_type == BLOCK_CORRUPT_00) {
        sync_hdr == SYNC_HDR_ERR_00;
      } else {
        sync_hdr == SYNC_HDR_ERR_11;
      }
    } else {
      sync_hdr inside {SYNC_HDR_ERR_00, SYNC_HDR_ERR_11};
    }
  }

  // SKP Ordered Set Symbol Generation
  constraint c_skp_payload {
    if (is_skp_os) {
      block_type == BLOCK_ORDERED_SET;
      raw_payload[31:0] == SKP_PATTERN_32;
    }
  }

  // TLP Length distribution: 1 DW up to 64 DW typical
  constraint c_tlp_length {
    tlp_length_dw inside {[1:64]};
  }

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "pcie_seq_item");
    super.new(name);
  endfunction

  // ---------------------------------------------------------------------------
  // Convert to String for Logging
  // ---------------------------------------------------------------------------
  virtual function string convert2string();
    return $sformatf("Type=%s SyncHdr=2'b%02b Data=0x%032h SKP=%0d PPM=%0d",
                     block_type.name(), sync_hdr, raw_payload, is_skp_os, clock_drift_ppm);
  endfunction

endclass : pcie_seq_item

`endif // PCIE_SEQ_ITEM_SV
