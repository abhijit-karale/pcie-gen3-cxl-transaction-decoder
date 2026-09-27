# =============================================================================
# Company / Author: Abhijit Karale
# Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
# File: constraints.sdc
# Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
# Description: High-speed SDC timing constraints. Enforces 250 MHz (4.0 ns)
#              timing on rx_pclk and sys_clk, asynchronous clock groups,
#              CDC bus skew limits, and I/O timing budgets.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Clock Definitions (250 MHz -> Period = 4.000 ns)
# -----------------------------------------------------------------------------
# rx_pclk: Recovered clock from PHY CDR (+/- 300 ppm tolerance)
create_clock -name rx_pclk -period 4.000 [get_ports rx_pclk]

# sys_clk: Local core link clock (250 MHz nominal)
create_clock -name sys_clk -period 4.000 [get_ports sys_clk]

# -----------------------------------------------------------------------------
# 2. Clock Uncertainties, Jitter & Transitions
# -----------------------------------------------------------------------------
# 200 ps setup uncertainty (margin + jitter), 50 ps hold margin
set_clock_uncertainty -setup 0.200 [get_clocks {rx_pclk sys_clk}]
set_clock_uncertainty -hold  0.050 [get_clocks {rx_pclk sys_clk}]

# 80 ps clock slew transition
set_clock_transition 0.080 [get_clocks {rx_pclk sys_clk}]

# -----------------------------------------------------------------------------
# 3. Asynchronous Clock Domain Crossing (CDC) Relationship
# rx_pclk and sys_clk are mesochronous / asynchronous with +/- 300 ppm drift
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks rx_pclk] \
  -group [get_clocks sys_clk]

# -----------------------------------------------------------------------------
# 4. CDC Datapath & Bus Skew Constraints on Gray Synchronizer Flops
# Prevents excessive latency and skew across Gray pointer buses
# -----------------------------------------------------------------------------
# Maximum delay across CDC synchronizer boundaries (1 clock cycle datapath)
set_max_delay 4.000 -from [get_cells -hierarchical *ptr_gray_q_reg*] \
                    -to   [get_cells -hierarchical *ptr_gray_sync*1_reg*] \
                    -datapath_only

# Max bus skew across Gray pointer bits: <= 1.0 ns to prevent multi-bit sampling
set_bus_skew 1.000  -from [get_cells -hierarchical *ptr_gray_q_reg*] \
                    -to   [get_cells -hierarchical *ptr_gray_sync*1_reg*]

# -----------------------------------------------------------------------------
# 5. Input Timing Constraints (Budget: 30% of 4.0 ns = 1.2 ns max delay)
# -----------------------------------------------------------------------------
set_input_delay -clock rx_pclk -max 1.200 [get_ports {rx_valid_i rx_sync_hdr_i* rx_data_i* descramble_en_i seed_load_i seed_val_i*}]
set_input_delay -clock rx_pclk -min 0.300 [get_ports {rx_valid_i rx_sync_hdr_i* rx_data_i* descramble_en_i seed_load_i seed_val_i*}]

# -----------------------------------------------------------------------------
# 6. Output Timing Constraints (Budget: 30% of 4.0 ns = 1.2 ns max delay)
# -----------------------------------------------------------------------------
# TLP streaming interface (sys_clk domain)
set_output_delay -clock sys_clk -max 1.200 [get_ports {tlp_valid_o tlp_start_o tlp_end_o tlp_data_o* tlp_keep_o* tlp_seq_num_o* tlp_length_dw_o* tlp_header_o* tlp_is_4dw_o tlp_error_o tlp_lcrc_err_o tlp_stp_err_o}]
set_output_delay -clock sys_clk -min 0.300 [get_ports {tlp_valid_o tlp_start_o tlp_end_o tlp_data_o* tlp_keep_o* tlp_seq_num_o* tlp_length_dw_o* tlp_header_o* tlp_is_4dw_o tlp_error_o tlp_lcrc_err_o tlp_stp_err_o}]

# Status telemetry in sys_clk domain
set_output_delay -clock sys_clk -max 1.200 [get_ports {fifo_empty_o fifo_underflow_err_o rd_occupancy_o* skp_inserted_cnt_o* tlp_success_cnt_o* tlp_error_cnt_o*}]
set_output_delay -clock sys_clk -min 0.300 [get_ports {fifo_empty_o fifo_underflow_err_o rd_occupancy_o* skp_inserted_cnt_o* tlp_success_cnt_o* tlp_error_cnt_o*}]

# Status telemetry in rx_pclk domain
set_output_delay -clock rx_pclk -max 1.200 [get_ports {block_lock_o sync_header_err_o link_recovery_req_o fifo_full_o fifo_overflow_err_o wr_occupancy_o* skp_deleted_cnt_o* corrupt_hdr_cnt_o* valid_block_cnt_o*}]
set_output_delay -clock rx_pclk -min 0.300 [get_ports {block_lock_o sync_header_err_o link_recovery_req_o fifo_full_o fifo_overflow_err_o wr_occupancy_o* skp_deleted_cnt_o* corrupt_hdr_cnt_o* valid_block_cnt_o*}]

# -----------------------------------------------------------------------------
# 7. Environmental & Electrical Drive/Load Constraints
# -----------------------------------------------------------------------------
set_max_fanout 16 [current_design]
set_max_transition 0.350 [current_design]
set_load -pin_load 0.020 [all_outputs]
