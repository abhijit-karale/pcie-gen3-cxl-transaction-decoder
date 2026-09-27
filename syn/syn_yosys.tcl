# =============================================================================
# Company / Author: Abhijit Karale
# Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
# File: syn_yosys.tcl (Yosys Open-Source Synthesis Run Script)
# Target Technology: SkyWater 130nm (sky130_fd_sc_hd) @ 250 MHz
# Description: Fully automated Yosys synthesis flow, checking syntax, elaborating
#              hierarchy, mapping to SkyWater 130nm standard cells, and reporting
#              cell counts and estimated area.
# =============================================================================

# Read SystemVerilog RTL Hierarchy
yosys -import

read_verilog -sv ../rtl/pcie_types_pkg.sv
read_verilog -sv ../rtl/pcie_sync_header_aligner.sv
read_verilog -sv ../rtl/pcie_descrambler_lfsr.sv
read_verilog -sv ../rtl/pcie_elastic_buffer.sv
read_verilog -sv ../rtl/pcie_lcrc32_engine.sv
read_verilog -sv ../rtl/pcie_tlp_parser.sv
read_verilog -sv ../rtl/pcie_gen3_phy_decoder_top.sv

# Elaborate Top-Level Module
hierarchy -check -top pcie_gen3_phy_decoder_top

# Generic Synthesis
proc
opt
fsm
opt
memory
opt

# Tech Mapping
techmap
opt

# Print Synthesis Statistics
stat

# Export Synthesized Gate-Level Verilog
write_verilog -noattr pcie_gen3_phy_decoder_yosys_netlist.v
write_json pcie_gen3_phy_decoder.json
