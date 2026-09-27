// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_coverage
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: Comprehensive functional coverage model covering sync header
//              encodings, PPM clock drift bounds, SKP ordered set handling,
//              TLP header formats, length bins, and LCRC error injection.
// =============================================================================

`ifndef PCIE_COVERAGE_SV
`define PCIE_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

class pcie_coverage extends uvm_subscriber #(pcie_seq_item);

  `uvm_component_utils(pcie_coverage)

  // ---------------------------------------------------------------------------
  // Covergroup 1: 128b/130b Sync Header Encodings & Transitions
  // ---------------------------------------------------------------------------
  covergroup cg_sync_headers with function sample(logic [1:0] sync_hdr);
    option.per_instance = 1;
    option.comment      = "128b/130b Sync Header Encodings Coverage";

    cp_sync_hdr: coverpoint sync_hdr {
      bins data_block        = {SYNC_HDR_DATA};
      bins ordered_set_block = {SYNC_HDR_ORDERED_SET};
      bins corrupt_header_00 = {SYNC_HDR_ERR_00};
      bins corrupt_header_11 = {SYNC_HDR_ERR_11};
    }

    cp_transitions: coverpoint sync_hdr {
      bins data_to_os      = (SYNC_HDR_DATA => SYNC_HDR_ORDERED_SET);
      bins os_to_data      = (SYNC_HDR_ORDERED_SET => SYNC_HDR_DATA);
      bins data_to_corrupt = (SYNC_HDR_DATA => SYNC_HDR_ERR_00, SYNC_HDR_ERR_11);
      bins corrupt_to_data = (SYNC_HDR_ERR_00, SYNC_HDR_ERR_11 => SYNC_HDR_DATA);
    }
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 2: PPM Clock Frequency Drift Bounds (-300 to +300 ppm)
  // ---------------------------------------------------------------------------
  covergroup cg_clock_drift with function sample(int ppm, logic is_skp);
    option.per_instance = 1;
    option.comment      = "PPM Clock Jitter & Elastic Tolerance Coverage";

    cp_ppm_range: coverpoint ppm {
      bins neg_extreme_ppm = {[-300:-200]};
      bins neg_moderate_ppm= {[-199:-50]};
      bins nominal_ppm     = {[-49:49]};
      bins pos_moderate_ppm= {[50:199]};
      bins pos_extreme_ppm = {[200:300]};
    }

    cp_skp_presence: coverpoint is_skp {
      bins no_skp = {1'b0};
      bins is_skp = {1'b1};
    }

    // Cross: Extreme PPM conditions with SKP Ordered Sets present
    cross_ppm_skp: cross cp_ppm_range, cp_skp_presence;
  endgroup

  // ---------------------------------------------------------------------------
  // Covergroup 3: TLP Packet Characteristics & Corruption
  // ---------------------------------------------------------------------------
  covergroup cg_tlp_packets with function sample(logic [9:0] len_dw, logic is_4dw, logic lcrc_err);
    option.per_instance = 1;
    option.comment      = "TLP Packet Length, Header, and Error Coverage";

    cp_len: coverpoint len_dw {
      bins single_dw   = {1};
      bins small_burst = {[2:8]};
      bins med_burst   = {[9:32]};
      bins large_burst = {[33:64]};
    }

    cp_header_type: coverpoint is_4dw {
      bins header_3dw = {1'b0};
      bins header_4dw = {1'b1};
    }

    cp_lcrc_status: coverpoint lcrc_err {
      bins lcrc_valid     = {1'b0};
      bins lcrc_corrupted = {1'b1};
    }

    cross_len_err: cross cp_len, cp_lcrc_status;
  endgroup

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name = "pcie_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_sync_headers = new();
    cg_clock_drift  = new();
    cg_tlp_packets  = new();
  endfunction

  // ---------------------------------------------------------------------------
  // Sampling Method
  // ---------------------------------------------------------------------------
  virtual function void write(pcie_seq_item t);
    cg_sync_headers.sample(t.sync_hdr);
    cg_clock_drift.sample(t.clock_drift_ppm, t.is_skp_os);
    if (t.is_tlp_start) begin
      cg_tlp_packets.sample(t.tlp_length_dw, t.is_4dw, t.corrupt_lcrc);
    end
  endfunction

endclass : pcie_coverage

`endif // PCIE_COVERAGE_SV
