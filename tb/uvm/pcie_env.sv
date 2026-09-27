// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_env
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM verification environment connecting the agent and scoreboard.
// =============================================================================

`ifndef PCIE_ENV_SV
`define PCIE_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_agent.sv"
`include "pcie_scoreboard.sv"

class pcie_env extends uvm_env;

  `uvm_component_utils(pcie_env)

  pcie_agent      agent;
  pcie_scoreboard scoreboard;

  function new(string name = "pcie_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = pcie_agent::type_id::create("agent", this);
    scoreboard = pcie_scoreboard::type_id::create("scoreboard", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.input_block_ap.connect(scoreboard.rx_block_export);
    agent.monitor.tlp_egress_ap.connect(scoreboard.tlp_egress_export);
  endfunction

endclass : pcie_env

`endif // PCIE_ENV_SV
