// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_agent
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM agent encapsulating driver, sequencer, monitor, and coverage.
// =============================================================================

`ifndef PCIE_AGENT_SV
`define PCIE_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"
`include "pcie_sequencer.sv"
`include "pcie_driver.sv"
`include "pcie_monitor.sv"
`include "pcie_coverage.sv"

class pcie_agent extends uvm_agent;

  `uvm_component_utils(pcie_agent)

  pcie_sequencer sequencer;
  pcie_driver    driver;
  pcie_monitor   monitor;
  pcie_coverage  coverage;

  function new(string name = "pcie_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = pcie_monitor::type_id::create("monitor", this);

    if (get_is_active() == UVM_ACTIVE) begin
      sequencer = pcie_sequencer::type_id::create("sequencer", this);
      driver    = pcie_driver::type_id::create("driver", this);
      coverage  = pcie_coverage::type_id::create("coverage", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.input_block_ap.connect(coverage.analysis_export);
    end
  endfunction

endclass : pcie_agent

`endif // PCIE_AGENT_SV
