// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_sequencer
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM sequencer orchestrating transaction sequences.
// =============================================================================

`ifndef PCIE_SEQUENCER_SV
`define PCIE_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

class pcie_sequencer extends uvm_sequencer #(pcie_seq_item);

  `uvm_component_utils(pcie_sequencer)

  function new(string name = "pcie_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : pcie_sequencer

`endif // PCIE_SEQUENCER_SV
