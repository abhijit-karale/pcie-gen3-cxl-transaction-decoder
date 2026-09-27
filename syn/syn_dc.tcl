# =============================================================================
# Company / Author: Abhijit Karale
# Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
# File: syn_dc.tcl (Synopsys Design Compiler Synthesis Run Script)
# Target Technology: FreePDK45 / Generic Standard Cell Library @ 250 MHz
# Description: Synthesis execution, ultra compilation, timing slack reporting,
#              area breakdown, and netlist export.
# =============================================================================

# Set Target & Link Libraries
set target_library [list "gscl45nm.db"]
set link_library   [list "*" "gscl45nm.db"]

# Define Search Path
set_app_var search_path [concat $search_path ../rtl]

# Define Top-Level Module
set TOP_MODULE "pcie_gen3_phy_decoder_top"

# Read SystemVerilog RTL Files
analyze -format sverilog [list \
  ../rtl/pcie_types_pkg.sv \
  ../rtl/pcie_sync_header_aligner.sv \
  ../rtl/pcie_descrambler_lfsr.sv \
  ../rtl/pcie_elastic_buffer.sv \
  ../rtl/pcie_lcrc32_engine.sv \
  ../rtl/pcie_tlp_parser.sv \
  ../rtl/pcie_gen3_phy_decoder_top.sv \
]

# Elaborate Architecture
elaborate $TOP_MODULE
current_design $TOP_MODULE
link

# Check Unresolved References
check_design > check_design.rpt

# Apply Timing Constraints
source constraints.sdc

# Synthesis Optimization with Clock Gating & High Effort
compile_ultra -gate_clock -no_autoungroup

# Generate Detailed Synthesis Quality of Results (QoR) Reports
report_timing -delay_type max -max_paths 20 -significant_digits 3 > timing_max_setup.rpt
report_timing -delay_type min -max_paths 20 -significant_digits 3 > timing_min_hold.rpt
report_area -hierarchy                                           > area_hierarchy.rpt
report_power -hierarchy                                          > power_hierarchy.rpt
report_constraint -all_violators                                 > constraint_violations.rpt
report_qor                                                       > qor_summary.rpt

# Export Synthesized Gate-Level Netlist & SDC
write -format verilog -hierarchy -output "${TOP_MODULE}_netlist.v"
write -format ddc     -hierarchy -output "${TOP_MODULE}.ddc"
write_sdc "${TOP_MODULE}_syn.sdc"

puts "\n========================================================"
puts " Synopsys DC Synthesis Completed Successfully!"
puts " Target Clock: 250 MHz (4.000 ns)"
puts " Target Tech : FreePDK45"
puts " Top Module  : $TOP_MODULE"
puts "========================================================\n"
exit
