// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_driver
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM driver converting transaction items into physical 128b/130b
//              signals on rx_pclk, dynamically applying +/- 300 ppm clock jitter.
// =============================================================================

`ifndef PCIE_DRIVER_SV
`define PCIE_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

class pcie_driver extends uvm_driver #(pcie_seq_item);

  `uvm_component_utils(pcie_driver)

  virtual pcie_if vif;

  function new(string name = "pcie_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pcie_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NO_VIF", "Virtual interface pcie_if not found in config_db!")
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    reset_signals();
    wait_reset_release();

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task reset_signals();
    vif.rx_valid        <= 1'b0;
    vif.rx_sync_hdr     <= 2'b00;
    vif.rx_data         <= '0;
    vif.descramble_en   <= 1'b1;
    vif.seed_load       <= 1'b0;
    vif.seed_val        <= LFSR_LANE0_SEED;
    vif.clock_drift_ppm <= 0;
  endtask

  virtual task wait_reset_release();
    @(posedge vif.rx_pclk);
    while (!vif.rx_rst_n) @(posedge vif.rx_pclk);
    @(posedge vif.rx_pclk);
  endtask

  virtual task drive_item(pcie_seq_item item);
    // Apply requested clock drift parameter to interface for jitter modulation
    vif.clock_drift_ppm <= item.clock_drift_ppm;

    @(posedge vif.rx_pclk);
    vif.rx_valid    <= 1'b1;
    vif.rx_sync_hdr <= item.sync_hdr;
    vif.rx_data     <= item.raw_payload;

    `uvm_info(get_type_name(), $sformatf("Driving Block: %s", item.convert2string()), UVM_HIGH)
  endtask

endclass : pcie_driver

`endif // PCIE_DRIVER_SV
