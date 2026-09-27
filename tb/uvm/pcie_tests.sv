// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_tests
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: UVM test suite containing base test and specialized test cases:
//              sanity bring-up, PPM jitter tolerance, sync header corruption,
//              and random stress testing.
// =============================================================================

`ifndef PCIE_TESTS_SV
`define PCIE_TESTS_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_env.sv"
`include "pcie_sequences.sv"

// -----------------------------------------------------------------------------
// Base Test
// -----------------------------------------------------------------------------
class pcie_base_test extends uvm_test;
  `uvm_component_utils(pcie_base_test)

  pcie_env env;

  function new(string name = "pcie_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = pcie_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction
endclass : pcie_base_test

// -----------------------------------------------------------------------------
// Test 1: Sanity Test
// -----------------------------------------------------------------------------
class pcie_sanity_test extends pcie_base_test;
  `uvm_component_utils(pcie_sanity_test)

  function new(string name = "pcie_sanity_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    pcie_sanity_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting PCIe Gen3 Sanity Test...", UVM_LOW)
    seq = pcie_sanity_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #100ns;
    phase.drop_objection(this);
  endtask
endclass : pcie_sanity_test

// -----------------------------------------------------------------------------
// Test 2: PPM Clock Jitter & Elastic Tolerance Test (+/- 300 ppm)
// -----------------------------------------------------------------------------
class pcie_ppm_drift_test extends pcie_base_test;
  `uvm_component_utils(pcie_ppm_drift_test)

  function new(string name = "pcie_ppm_drift_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    pcie_ppm_jitter_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting +/- 300 ppm Clock Tolerance Test...", UVM_LOW)
    seq = pcie_ppm_jitter_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #200ns;
    phase.drop_objection(this);
  endtask
endclass : pcie_ppm_drift_test

// -----------------------------------------------------------------------------
// Test 3: Sync Header Corruption & Link Recovery Test
// -----------------------------------------------------------------------------
class pcie_sync_header_err_test extends pcie_base_test;
  `uvm_component_utils(pcie_sync_header_err_test)

  function new(string name = "pcie_sync_header_err_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    pcie_sync_corruption_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Sync Header Corruption Test...", UVM_LOW)
    seq = pcie_sync_corruption_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #100ns;
    phase.drop_objection(this);
  endtask
endclass : pcie_sync_header_err_test

// -----------------------------------------------------------------------------
// Test 4: Full Constrained-Random Stress Test
// -----------------------------------------------------------------------------
class pcie_tlp_stress_test extends pcie_base_test;
  `uvm_component_utils(pcie_tlp_stress_test)

  function new(string name = "pcie_tlp_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    pcie_stress_random_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Constrained-Random Stress Test...", UVM_LOW)
    seq = pcie_stress_random_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);
    #300ns;
    phase.drop_objection(this);
  endtask
endclass : pcie_tlp_stress_test

`endif // PCIE_TESTS_SV
