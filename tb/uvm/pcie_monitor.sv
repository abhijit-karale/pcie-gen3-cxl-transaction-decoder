// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_monitor
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM monitor sampling physical 128b/130b inputs on rx_pclk and
//              decoded TLP packets on sys_clk, broadcasting to analysis ports.
// =============================================================================

`ifndef PCIE_MONITOR_SV
`define PCIE_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

class pcie_monitor extends uvm_monitor;

  `uvm_component_utils(pcie_monitor)

  virtual pcie_if vif;

  // Analysis ports for scoreboard and coverage
  uvm_analysis_port #(pcie_seq_item) input_block_ap;
  uvm_analysis_port #(pcie_seq_item) tlp_egress_ap;

  function new(string name = "pcie_monitor", uvm_component parent = null);
    super.new(name, parent);
    input_block_ap = new("input_block_ap", this);
    tlp_egress_ap  = new("tlp_egress_ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", "Virtual interface pcie_if not found in config_db!")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    fork
      monitor_rx_blocks();
      monitor_tlp_egress();
    join
  endtask

  // Monitor physical RX blocks on rx_pclk
  virtual task monitor_rx_blocks();
    pcie_seq_item item;
    forever begin
      @(posedge vif.rx_pclk);
      if (vif.rx_rst_n && vif.rx_valid) begin
        item = pcie_seq_item::type_id::create("rx_item");
        item.sync_hdr        = vif.rx_sync_hdr;
        item.raw_payload     = vif.rx_data;
        item.clock_drift_ppm = vif.clock_drift_ppm;

        case (vif.rx_sync_hdr)
          SYNC_HDR_DATA:        item.block_type = BLOCK_DATA;
          SYNC_HDR_ORDERED_SET: item.block_type = BLOCK_ORDERED_SET;
          SYNC_HDR_ERR_00:      item.block_type = BLOCK_CORRUPT_00;
          SYNC_HDR_ERR_11:      item.block_type = BLOCK_CORRUPT_11;
        endcase

        item.is_skp_os = (vif.rx_sync_hdr == SYNC_HDR_ORDERED_SET) &&
                         (vif.rx_data[31:0] == SKP_PATTERN_32);

        input_block_ap.write(item);
      end
    end
  endtask

  // Monitor decoded TLP egress on sys_clk
  virtual task monitor_tlp_egress();
    pcie_seq_item item;
    forever begin
      @(posedge vif.sys_clk);
      if (vif.sys_rst_n && vif.tlp_valid && vif.tlp_end) begin
        item = pcie_seq_item::type_id::create("tlp_egress_item");
        item.tlp_seq_num     = vif.tlp_seq_num;
        item.tlp_length_dw   = vif.tlp_length_dw;
        item.tlp_header      = vif.tlp_header;
        item.is_4dw          = vif.tlp_is_4dw;
        item.corrupt_lcrc    = vif.tlp_lcrc_err;
        item.corrupt_sync_hdr= 1'b0;

        tlp_egress_ap.write(item);
        `uvm_info("MON_TLP", $sformatf("Captured Decoded TLP: Seq=%0d Len=%0d LCRC_Err=%0d STP_Err=%0d",
                  vif.tlp_seq_num, vif.tlp_length_dw, vif.tlp_lcrc_err, vif.tlp_stp_err), UVM_MEDIUM)
      end
    end
  endtask

endclass : pcie_monitor

`endif // PCIE_MONITOR_SV
