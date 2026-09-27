# =============================================================================
# Company / Author: Abhijit Karale
# Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
# Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
# File: Makefile
# Description: Production Makefile supporting simulation (Standalone & UVM),
#              formal verification (JasperGold & SymbiYosys), linting,
#              synthesis (Design Compiler & Yosys), and regression runs.
# =============================================================================

SHELL := /bin/bash
PYTHON ?= python

# Directories
RTL_DIR      := rtl
TB_DIR       := tb
UVM_DIR      := $(TB_DIR)/uvm
FORMAL_DIR   := $(TB_DIR)/formal
STANDALONE_DIR:= $(TB_DIR)/standalone
MODEL_DIR    := $(TB_DIR)/model
SYN_DIR      := syn
BUILD_DIR    := build

# RTL Sources
RTL_SRCS := $(RTL_DIR)/pcie_types_pkg.sv \
            $(RTL_DIR)/pcie_sync_header_aligner.sv \
            $(RTL_DIR)/pcie_descrambler_lfsr.sv \
            $(RTL_DIR)/pcie_elastic_buffer.sv \
            $(RTL_DIR)/pcie_lcrc32_engine.sv \
            $(RTL_DIR)/pcie_tlp_parser.sv \
            $(RTL_DIR)/pcie_gen3_phy_decoder_top.sv

.PHONY: all help sim_ref sim_standalone sim_uvm formal_jg formal_sby synth_dc synth_yosys lint clean

all: sim_ref

help:
	@echo "============================================================================="
	@echo " PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder Build System"
	@echo " Author: Abhijit Karale | Target: SkyWater 130nm / FreePDK45 @ 250 MHz"
	@echo "============================================================================="
	@echo " Available Targets:"
	@echo "   make sim_ref        : Run bit-accurate Python reference verification suite"
	@echo "   make sim_standalone : Run standalone self-checking SV testbench (Icarus/VCS/Questa)"
	@echo "   make sim_uvm        : Run layered UVM 1.2 testbench (Synopsys VCS)"
	@echo "   make sim_uvm_quest  : Run layered UVM 1.2 testbench (Siemens Questa / ModelSim)"
	@echo "   make formal_jg      : Run Cadence JasperGold formal proof (Zero Pointer Inversion)"
	@echo "   make formal_sby     : Run SymbiYosys open-source formal proof (SVA / Z3)"
	@echo "   make synth_dc       : Run Synopsys Design Compiler synthesis (FreePDK45 @ 250 MHz)"
	@echo "   make synth_yosys    : Run Yosys open-source synthesis (SkyWater 130nm)"
	@echo "   make lint           : Run Verilator RTL linting and code quality analysis"
	@echo "   make clean          : Remove all simulation and synthesis temporary files"
	@echo "============================================================================="

# -----------------------------------------------------------------------------
# 1. Python Bit-Accurate Reference Model
# -----------------------------------------------------------------------------
sim_ref:
	@echo "[BUILD] Running bit-accurate reference model and protocol checks..."
	$(PYTHON) $(MODEL_DIR)/pcie_ref_model.py

# -----------------------------------------------------------------------------
# 2. Standalone SystemVerilog Simulation
# -----------------------------------------------------------------------------
sim_standalone:
	@mkdir -p $(BUILD_DIR)
	@if command -v iverilog >/dev/null 2>&1; then \
		echo "[BUILD] Compiling with Icarus Verilog..."; \
		iverilog -g2012 -o $(BUILD_DIR)/sim_standalone.vvp $(RTL_SRCS) $(STANDALONE_DIR)/tb_standalone_top.sv && \
		vvp $(BUILD_DIR)/sim_standalone.vvp; \
	elif command -v vcs >/dev/null 2>&1; then \
		echo "[BUILD] Compiling with Synopsys VCS..."; \
		vcs -sverilog -full64 -timescale=1ns/1ps $(RTL_SRCS) $(STANDALONE_DIR)/tb_standalone_top.sv -o $(BUILD_DIR)/simv && \
		$(BUILD_DIR)/simv; \
	else \
		echo "[WARNING] Neither iverilog nor vcs found in PATH. Running Python bit-accurate model:"; \
		$(PYTHON) $(MODEL_DIR)/pcie_ref_model.py; \
	fi

# -----------------------------------------------------------------------------
# 3. Layered UVM 1.2 Simulation (Synopsys VCS)
# -----------------------------------------------------------------------------
sim_uvm:
	@mkdir -p $(BUILD_DIR)
	vcs -sverilog -ntb_opts uvm-1.2 -full64 -timescale=1ns/1ps \
		+incdir+$(RTL_DIR)+$(UVM_DIR) \
		$(RTL_SRCS) $(UVM_DIR)/tb_top.sv \
		-o $(BUILD_DIR)/uvm_simv
	$(BUILD_DIR)/uvm_simv +UVM_TESTNAME=pcie_tlp_stress_test +UVM_VERBOSITY=UVM_LOW

# -----------------------------------------------------------------------------
# 4. Layered UVM 1.2 Simulation (Siemens Questa)
# -----------------------------------------------------------------------------
sim_uvm_quest:
	@mkdir -p $(BUILD_DIR)/work
	vlib $(BUILD_DIR)/work
	vlog -sv -timescale "1ns/1ps" +incdir+$(RTL_DIR)+$(UVM_DIR) $(RTL_SRCS) $(UVM_DIR)/tb_top.sv -work $(BUILD_DIR)/work
	vsim -c -do "run -all; quit" tb_top +UVM_TESTNAME=pcie_tlp_stress_test -work $(BUILD_DIR)/work

# -----------------------------------------------------------------------------
# 5. Formal Verification (Cadence JasperGold)
# -----------------------------------------------------------------------------
formal_jg:
	cd $(FORMAL_DIR) && jg -tcl run_jg.tcl -batch

# -----------------------------------------------------------------------------
# 6. Formal Verification (SymbiYosys Open-Source)
# -----------------------------------------------------------------------------
formal_sby:
	cd $(FORMAL_DIR) && sby -f formal.sby

# -----------------------------------------------------------------------------
# 7. Synthesis (Synopsys Design Compiler)
# -----------------------------------------------------------------------------
synth_dc:
	cd $(SYN_DIR) && dc_shell -f syn_dc.tcl | tee dc_synth.log

# -----------------------------------------------------------------------------
# 8. Synthesis (Yosys Open-Source / SkyWater 130nm)
# -----------------------------------------------------------------------------
synth_yosys:
	cd $(SYN_DIR) && yosys -s syn_yosys.tcl | tee yosys_synth.log

# -----------------------------------------------------------------------------
# 9. Linting (Verilator)
# -----------------------------------------------------------------------------
lint:
	verilator --lint-only -Wall --timing $(RTL_SRCS) --top-module pcie_gen3_phy_decoder_top

# -----------------------------------------------------------------------------
# 10. Clean
# -----------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) *.vcd *.fsdb *.log *.key vc_hdrs.h DVEfiles ucli.key
	rm -rf $(SYN_DIR)/*.rpt $(SYN_DIR)/*.v $(SYN_DIR)/*.ddc $(SYN_DIR)/*.sdc $(SYN_DIR)/*.log $(SYN_DIR)/*.json
	rm -rf $(FORMAL_DIR)/jgproject $(FORMAL_DIR)/*.rpt $(FORMAL_DIR)/formal
