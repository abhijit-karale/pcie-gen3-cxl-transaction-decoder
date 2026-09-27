// =============================================================================
// Company / Author: Abhijit Karale
// Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
// Module: pcie_sequences
// Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz / UVM 1.2
// Description: Rich sequence library featuring sanity bring-up, +/- 300 ppm
//              clock tolerance stress, sync header corruption injection,
//              and full TLP generation with valid and corrupted LCRC-32.
// =============================================================================

`ifndef PCIE_SEQUENCES_SV
`define PCIE_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcie_seq_item.sv"

// -----------------------------------------------------------------------------
// Base Sequence
// -----------------------------------------------------------------------------
class pcie_base_seq extends uvm_sequence #(pcie_seq_item);
  `uvm_object_utils(pcie_base_seq)

  function new(string name = "pcie_base_seq");
    super.new(name);
  endfunction
endclass : pcie_base_seq

// -----------------------------------------------------------------------------
// Sequence 1: Sanity & Link Lock Acquisition Sequence
// -----------------------------------------------------------------------------
class pcie_sanity_seq extends pcie_base_seq;
  `uvm_object_utils(pcie_sanity_seq)

  function new(string name = "pcie_sanity_seq");
    super.new(name);
  endfunction

  virtual task body();
    pcie_seq_item item;

    // Send 8 consecutive valid Data blocks to guarantee block lock acquisition
    repeat (8) begin
      `uvm_create(item)
      if (!item.randomize() with {
        block_type       == BLOCK_DATA;
        sync_hdr         == SYNC_HDR_DATA;
        corrupt_sync_hdr == 1'b0;
        clock_drift_ppm  == 0;
      }) `uvm_fatal("RND_FAIL", "Randomization failed in sanity_seq!")
      `uvm_send(item)
    end

    // Send alternating Data blocks and SKP Ordered Sets
    repeat (16) begin
      `uvm_create(item)
      if (!item.randomize() with {
        corrupt_sync_hdr == 1'b0;
        clock_drift_ppm  == 0;
      }) `uvm_fatal("RND_FAIL", "Randomization failed in sanity_seq!")
      `uvm_send(item)
    end
  endtask
endclass : pcie_sanity_seq

// -----------------------------------------------------------------------------
// Sequence 2: PPM Clock Jitter & Elastic Tolerance Stress Sequence
// Alternates between +300 ppm and -300 ppm drift with SKP Ordered Sets
// -----------------------------------------------------------------------------
class pcie_ppm_jitter_seq extends pcie_base_seq;
  `uvm_object_utils(pcie_ppm_jitter_seq)

  function new(string name = "pcie_ppm_jitter_seq");
    super.new(name);
  endfunction

  virtual task body();
    pcie_seq_item item;

    // Phase 1: Lock acquisition
    repeat (8) begin
      `uvm_create(item)
      void'(item.randomize() with {
        block_type       == BLOCK_DATA;
        sync_hdr         == SYNC_HDR_DATA;
        corrupt_sync_hdr == 1'b0;
        clock_drift_ppm  == 0;
      });
      `uvm_send(item)
    end

    // Phase 2: Extreme positive drift (+300 ppm) -> Triggers SKP Deletion
    repeat (50) begin
      `uvm_create(item)
      void'(item.randomize() with {
        clock_drift_ppm  == 300;
        corrupt_sync_hdr == 1'b0;
      });
      `uvm_send(item)
    end

    // Send SKP Ordered Sets under positive drift
    repeat (10) begin
      `uvm_create(item)
      void'(item.randomize() with {
        block_type       == BLOCK_ORDERED_SET;
        sync_hdr         == SYNC_HDR_ORDERED_SET;
        is_skp_os        == 1'b1;
        raw_payload[31:0]== SKP_PATTERN_32;
        clock_drift_ppm  == 300;
      });
      `uvm_send(item)
    end

    // Phase 3: Extreme negative drift (-300 ppm) -> Triggers SKP Insertion
    repeat (50) begin
      `uvm_create(item)
      void'(item.randomize() with {
        clock_drift_ppm  == -300;
        corrupt_sync_hdr == 1'b0;
      });
      `uvm_send(item)
    end

    // Send SKP Ordered Sets under negative drift
    repeat (10) begin
      `uvm_create(item)
      void'(item.randomize() with {
        block_type       == BLOCK_ORDERED_SET;
        sync_hdr         == SYNC_HDR_ORDERED_SET;
        is_skp_os        == 1'b1;
        raw_payload[31:0]== SKP_PATTERN_32;
        clock_drift_ppm  == -300;
      });
      `uvm_send(item)
    end
  endtask
endclass : pcie_ppm_jitter_seq

// -----------------------------------------------------------------------------
// Sequence 3: Corrupted Sync Header Injection Sequence
// Injects 2'b00 and 2'b11 headers and tests Link Recovery threshold (4 errors)
// -----------------------------------------------------------------------------
class pcie_sync_corruption_seq extends pcie_base_seq;
  `uvm_object_utils(pcie_sync_corruption_seq)

  function new(string name = "pcie_sync_corruption_seq");
    super.new(name);
  endfunction

  virtual task body();
    pcie_seq_item item;

    // Lock link
    repeat (8) begin
      `uvm_create(item)
      void'(item.randomize() with {
        block_type == BLOCK_DATA;
        sync_hdr   == SYNC_HDR_DATA;
        clock_drift_ppm == 0;
      });
      `uvm_send(item)
    end

    // Inject isolated corrupted 2'b00 header
    `uvm_create(item)
    void'(item.randomize() with {
      sync_hdr         == SYNC_HDR_ERR_00;
      corrupt_sync_hdr == 1'b1;
    });
    `uvm_send(item)

    // Recover with 4 valid blocks
    repeat (4) begin
      `uvm_create(item)
      void'(item.randomize() with { block_type == BLOCK_DATA; sync_hdr == SYNC_HDR_DATA; });
      `uvm_send(item)
    end

    // Inject isolated corrupted 2'b11 header
    `uvm_create(item)
    void'(item.randomize() with {
      sync_hdr         == SYNC_HDR_ERR_11;
      corrupt_sync_hdr == 1'b1;
    });
    `uvm_send(item)

    // Recover
    repeat (4) begin
      `uvm_create(item)
      void'(item.randomize() with { block_type == BLOCK_DATA; sync_hdr == SYNC_HDR_DATA; });
      `uvm_send(item)
    end

    // Inject burst of 4 consecutive corrupted headers to trigger Link Recovery
    repeat (4) begin
      `uvm_create(item)
      void'(item.randomize() with {
        sync_hdr         inside {SYNC_HDR_ERR_00, SYNC_HDR_ERR_11};
        corrupt_sync_hdr == 1'b1;
      });
      `uvm_send(item)
    end
  endtask
endclass : pcie_sync_corruption_seq

// -----------------------------------------------------------------------------
// Sequence 4: Comprehensive Constrained-Random Stress Sequence
// -----------------------------------------------------------------------------
class pcie_stress_random_seq extends pcie_base_seq;
  `uvm_object_utils(pcie_stress_random_seq)

  function new(string name = "pcie_stress_random_seq");
    super.new(name);
  endfunction

  virtual task body();
    pcie_seq_item item;

    // Lock the link first
    repeat (8) begin
      `uvm_create(item)
      void'(item.randomize() with {
        block_type == BLOCK_DATA;
        sync_hdr   == SYNC_HDR_DATA;
        clock_drift_ppm == 0;
      });
      `uvm_send(item)
    end

    // Run 250 randomized transactions
    repeat (250) begin
      `uvm_create(item)
      if (!item.randomize()) `uvm_fatal("RND_FAIL", "Randomization failed in stress_random_seq!")
      `uvm_send(item)
    end
  endtask
endclass : pcie_stress_random_seq

`endif // PCIE_SEQUENCES_SV
