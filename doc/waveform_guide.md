# Cycle-Accurate Waveform Guide
## PCIe Gen3 / CXL 2.0 Elastic Buffer & Transaction Decoder Timing Traces

This document provides cycle-by-cycle ASCII waveform traces illustrating key dynamic events within the decoder pipeline, focusing on:
1. Clock tolerance compensation via SKP Ordered Set removal (swallowing) at $+300\text{ ppm}$ clock drift.
2. Clock tolerance compensation via SKP Ordered Set insertion (duplication) at $-300\text{ ppm}$ clock drift.
3. Corrupted Sync Header detection, reporting, and link recovery thresholding.
4. TLP boundary identification, STP token decoding, payload streaming, and LCRC-32 verification.

---

### 1. SKP Ordered Set Removal (Deletion) During $+300\text{ ppm}$ Clock Drift

#### Scenario
The receiver clock (`rx_pclk`) runs $300\text{ ppm}$ faster than the local system clock (`sys_clk`).
Over time, writes outpace reads, driving the elastic buffer FIFO occupancy above `HIGH_WATERMARK` (24 entries).
When an incoming block is identified as a SKP Ordered Set (`sync_hdr == 2'b10` and `data[31:0] == 32'hAA_AA_AA_AA`), the write logic suppresses writing to the FIFO (`wr_en = 0`), swallowing the SKP Ordered Set and dropping the occupancy back towards nominal.

```
Cycle (rx_pclk):     1       2       3       4       5       6       7       8       9
rx_pclk         : __/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \_
rx_valid        : ______/===============================================================\_
rx_sync_hdr     : ------X  01   X  01   X  01   X  10   X  10   X  01   X  01   X  01   X-
rx_data         : ------X D_N-1 X D_N   X D_N+1 X SKP_0 X SKP_1 X D_N+2 X D_N+3 X D_N+4 X-
is_skp_os       : ______________________________/\______/\________________________________
fifo_occupancy  : ------X  23   X  24   X  25   X  25   X  25   X  25   X  26   X  26   X-
high_watermark  : ======================================================================== (Value = 24)
skp_drop_trig   : ______________________________/=======/\________________________________
fifo_wr_en      : ______/=======================\_______/===============================\_
wr_ptr_bin      : ------X  10   X  11   X  12   X  12   X  13   X  14   X  15   X  16   X-
wr_ptr_gray     : ------X 01111 X 01110 X 01100 X 01100 X 01101 X 01001 X 01000 X 01000 X-
fifo_mem[12]    : ------------------------------X [PREV]X D_N+1 X ------------------------
fifo_mem[13]    : ----------------------------------------------X SKP_1 X ----------------

Note on Cycle 4:
- `fifo_occupancy` is 25 (> HIGH_WATERMARK = 24).
- `is_skp_os` is asserted for block `SKP_0`.
- `skp_drop_trig` pulses HIGH.
- `fifo_wr_en` is deasserted (forced to 0) despite `rx_valid` being HIGH.
- `wr_ptr_bin` remains at 12 (does NOT advance).
- `SKP_0` is discarded; pointer inversion is completely averted!
```

---

### 2. SKP Ordered Set Insertion (Duplication) During $-300\text{ ppm}$ Clock Drift

#### Scenario
The receiver clock (`rx_pclk`) runs $300\text{ ppm}$ slower than the local system clock (`sys_clk`).
Reads outpace writes, driving FIFO occupancy below `LOW_WATERMARK` (8 entries).
When reading a SKP Ordered Set, the read controller pauses incrementing the read pointer for one cycle (`rd_ptr` holds), replicating the SKP block to the downstream logic and boosting occupancy back towards nominal.

```
Cycle (sys_clk) :     1       2       3       4       5       6       7       8       9
sys_clk         : __/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \_
fifo_empty      : ________________________________________________________________________
fifo_occupancy  : ------X   9   X   8   X   7   X   7   X   7   X   8   X   8   X   9   X-
low_watermark   : ======================================================================== (Value = 8)
fifo_rdata      : ------X D_K-1 X D_K   X SKP_0 X SKP_0 X D_K+1 X D_K+2 X D_K+3 X D_K+4 X-
fifo_rdata_is_skp:______________________/===============\_________________________________
skp_insert_trig : ______________________/=======\_________________________________________
fifo_rd_en      : ______/===============\_______/=======================================\_
rd_ptr_bin      : ------X  04   X  05   X  06   X  06   X  07   X  08   X  09   X  10   X-
rd_ptr_gray     : ------X 00110 X 00111 X 00101 X 00101 X 00100 X 01100 X 01101 X 01111 X-
sys_valid_out   : ______/===============================================================\_
sys_data_out    : ------X D_K-1 X D_K   X SKP_0 X SKP_0 X D_K+1 X D_K+2 X D_K+3 X D_K+4 X-
                                          ^       ^
                                       Original  Duplicated

Note on Cycle 4:
- `fifo_occupancy` is 7 (< LOW_WATERMARK = 8).
- `fifo_rdata_is_skp` is detected.
- `skp_insert_trig` pulses HIGH.
- `fifo_rd_en` is held LOW; `rd_ptr_bin` remains at 6.
- The SKP Ordered Set is output for a second cycle, absorbing clock drift and preventing underflow.
```

---

### 3. Corrupted Sync Header Detection & Link Integrity Tracking

#### Scenario
A physical link perturbation corrupts the 2-bit Sync Header from `2'b01` to `2'b00` or `2'b11`.
The sync header aligner immediately flags `sync_header_err`, suppresses the invalid block from reaching the descrambler, and asserts `link_recovery_req` when the consecutive error count reaches 4.

```
Cycle (rx_pclk):     1       2       3       4       5       6       7       8       9
rx_pclk         : __/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \_
rx_valid        : ______/===============================================================\_
rx_sync_hdr     : ------X  01   X  00   X  11   X  00   X  00   X  01   X  01   X  01   X-
                        Valid   CORRUPT CORRUPT CORRUPT CORRUPT Valid   Valid   Valid
sync_header_err : ______________/=======================\_________________________________
err_counter     : ------X   0   X   1   X   2   X   3   X   4   X   0   X   0   X   0   X-
link_recovery_req:______________________________________/=======\_________________________
aligner_out_valid:______/=======\_______________________/===============================\_
aligner_out_data: ------X D_0   X       BLOCKED         X D_4   X D_5   X D_6   X D_7   X-
```

---

### 4. TLP Framing, STP Decoding, and 32-bit LCRC Verification

#### Scenario
An unaligned TLP arrives within 128-bit Data Blocks. The parser locates the STP framing token (`8'hF0`), decodes the sequence number and length, routes the payload through the LCRC-32 computation engine, and verifies the 32-bit CRC at packet termination.

```
Cycle (sys_clk) :     1       2       3       4       5       6       7       8
sys_clk         : __/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \___/ \_
data_in[127:0]  : ------X IDLE  X [STP|H0|H1|H2]X [P0 | P1 | P2 | P3] X [P4|P5|LCRC|IDLE]X-
stp_detect      : ______________/===============\___________________________________
stp_seq_num     : --------------X    12'h04A    X-----------------------------------
stp_len_dw      : --------------X    10'h006    X-----------------------------------
tlp_parser_state: IDLE  X IDLE  X     HEADER    X      PAYLOAD        X  CHECK_LCRC X
lcrc_engine_en  : ______________/=====================================\_____________
lcrc_accum[31:0]: 32'hFFFFFFFF  X 32'h8B3421A0  X 32'h5F109E2B        X 32'hC704DD7B(Residue)
lcrc_match      : ____________________________________________________/=============\
tlp_valid_out   : ____________________________________________________/=============\
tlp_error_out   : __________________________________________________________________ (0 = No Error)
tlp_seq_out     : ----------------------------------------------------X   12'h04A   X
```
