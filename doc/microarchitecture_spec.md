# PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
## Microarchitectural Specification & Architecture Document

### 1. Architectural Overview & Context
This IP implements a high-performance, synthesizable Physical Link Layer Transaction Decoder targeting PCIe Gen3 (8.0 GT/s) and Compute Express Link (CXL 1.1/2.0) native link transactions. Operating at 250 MHz across both a recovered clock domain (`rx_pclk`) and a local core system domain (`sys_clk`), it delivers 32 Gbps wire throughput across a 128-bit internal pipeline.

```
                           +-------------------------------------------------------+
                           |                  PHYSICAL LINK LAYER                  |
                           |             TRANSACTION DECODER PIPELINE              |
                           +-------------------------------------------------------+

  RAW 128b DATA + SYNC HDR
          | (rx_pclk ~ 250MHz +/- 300ppm)
          v
  +-------------------------------+
  |   pcie_sync_header_aligner    |  <-- 128b/130b Block Framing
  |                               |  <-- Validates Sync Header (01=Data, 10=OS)
  | - Corrupted Header Detector   |  <-- Detects Corrupted Headers (00, 11)
  | - Lock Acquisition FSM        |  <-- Tracks Block Alignment Lock
  +-------------------------------+
          |
          | rx_sync_hdr[1:0], rx_data[127:0], rx_valid, rx_block_type
          v
  +-------------------------------+
  |    pcie_descrambler_lfsr      |  <-- Polynomial: x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
  |                               |  <-- 128-bit Parallel Unrolled LFSR
  | - Ordered Set Bypass Logic    |  <-- Bypasses SKP/TS1/TS2 Ordered Sets
  | - Seed Reset Logic            |  <-- Synchronizes PRBS State on Framing Tokens
  +-------------------------------+
          |
          | descrambled_data[127:0], sync_hdr[1:0], block_type, valid
          v
  +-------------------------------+
  |      pcie_elastic_buffer      |  <-- Dual-Clock Asynchronous FIFO (Depth: 32)
  |                               |  <-- 3-Stage MTBF Gray Pointer CDC
  | - SKP Deletion Engine         |  <-- Swallows SKP OS when Occupancy > High Watermark (24)
  | - SKP Insertion Engine        |  <-- Injects/Replicates SKP OS when Occupancy < Low Watermark (8)
  | - Pointer Inversion-Free CDC  |  <-- Formally Proven Zero Pointer Reversal
  +-------------------------------+
          |
          | (sys_clk @ 250MHz Nominal)
          | sys_data[127:0], sys_sync_hdr[1:0], sys_is_data, sys_valid
          v
  +-------------------------------+
  |       pcie_tlp_parser         |  <-- DWORD (32-bit) Boundary Aligner
  |                               |  <-- STP Token Decoder (SeqNum, Length, Parity)
  | - Framing Boundary Extractor  |  <-- End of Packet (END / EDB) Detector
  | - Packet Accumulator / Stream |  <-- Emits Decoded TLP AXI-Stream-like Interface
  +-------------------------------+
          |
          +-------------------------------+
          |      pcie_lcrc32_engine       |  <-- PCIe 32-bit LCRC Generator & Checker
          |                               |  <-- Polynomial: 0x04C11DB7
          | - Parallel 128b LCRC Matrix   |  <-- Variable DWORD Byte-Enable Mask
          | - Residue Check (0xC704DD7B)  |  <-- Immediate Corrupted Packet Invalidation
          +-------------------------------+
          |
          v
  DECODED TLP EGRESS INTERFACE
  (tlp_valid, tlp_hdr[127:0], tlp_data[127:0], tlp_len, tlp_seq, tlp_error)
```

---

### 2. 128b/130b Block Framing & Sync Header Decoding

#### 2.1 Sync Header Encodings
In PCIe Gen3 and CXL 2.0, each 130-bit block consists of a 2-bit Sync Header followed by 128 bits (16 bytes) of payload:

| Sync Header `[1:0]` | Block Classification | Protocol Interpretation | Action Taken |
|:-------------------:|:--------------------:|:------------------------|:-------------|
| `2'b01` | Data Block | Contains TLPs, DLLPs, or IDLE 32-bit tokens | Forward to descrambler; scramble/descramble enabled |
| `2'b10` | Ordered Set Block | Contains SKP, TS1, TS2, EIOS, or FTS Ordered Sets | Forward to elastic buffer; descrambler bypassed |
| `2'b00` | Corrupted Header | Framing violation / Bit-slip / CDR error | Assert `sync_header_err`, increment error telemetry |
| `2'b11` | Corrupted Header | Framing violation / Inversion / CDR error | Assert `sync_header_err`, increment error telemetry |

#### 2.2 Block Alignment & Lock FSM
The aligner tracks lock state:
- **HUNT**: Search for valid sync headers (`2'b01` or `2'b10`).
- **PRE_LOCK**: Count 4 consecutive valid headers without error.
- **LOCKED**: Link locked. Consecutive corrupted sync headers trigger a counter. If 4 consecutive errors occur, block lock is dropped and Link Recovery is signaled.

---

### 3. Descrambler LFSR Architecture

#### 3.1 Polynomial Definition
The pseudo-random bit sequence (PRBS) generator polynomial defined by the PCIe Gen3 specification is:
$$G(x) = x^{23} + x^{21} + x^{16} + x^8 + x^5 + x^2 + 1$$

In hardware, a 23-bit Galois/Fibonacci LFSR is parallelized across 128 bits in a single 250 MHz clock cycle.

```
Feedback Equation for Bit 0:
F = S[22] ^ S[20] ^ S[15] ^ S[7] ^ S[4] ^ S[1] ^ S[0]
```

#### 3.2 Parallel Unrolling
Rather than advancing the LFSR 128 times sequentially across 128 clock pulses, the next state matrix $A^{128}$ and output mask $M[127:0]$ are evaluated combinatorially:
$$S_{t+128} = A^{128} \cdot S_t$$
$$Data_{plain}[127:0] = Data_{cipher}[127:0] \oplus Mask[127:0]$$

#### 3.3 Bypass and Seed Management
- **Ordered Sets**: Payload is passed verbatim ($Mask = 0$), and LFSR state advancement is frozen or re-seeded.
- **SKP Ordered Set**: When a SKP OS arrives, the LFSR seed is reset or re-initialized per PCIe Gen3 lane numbering rules (default seed: `23'h1DBFBC` for lane 0).
- **Data Blocks**: Payload is descrambled and the LFSR advances 128 bits per cycle.

---

### 4. Elastic Buffer & Clock Tolerance Compensation

#### 4.1 Frequency Tolerance Derivation
- Maximum Receiver Drift: $+300\text{ ppm}$
- Maximum Transmitter Drift: $-300\text{ ppm}$
- Total Worst-Case Drift: $\Delta f = 600\text{ ppm} = 6 \times 10^{-4}$
- At 250 MHz ($T = 4.0\text{ ns}$):
  $$\text{Cycle Slip Period} = \frac{1}{600 \times 10^{-6}} = 1666.67 \text{ clock cycles}$$
- One clock cycle differential accumulates every $1667$ cycles.
- PCIe Gen3 mandates SKP Ordered Sets sent every 370 to 375 blocks (~1500 cycles). Drift over this window:
  $$\text{Drift per SKP Interval} = 375 \times 6 \times 10^{-4} \approx 0.225 \text{ blocks}$$

#### 4.2 Elastic Buffer Specifications
- **Depth**: 32 entries (each entry: 128 bits data + 2 bits sync header + 2 bits metadata).
- **Nominal Fill Level**: 16 entries.
- **High Watermark (`HIGH_WATERMARK`)**: 24 entries.
- **Low Watermark (`LOW_WATERMARK`)**: 8 entries.
- **Clock Domain Crossing (CDC)**: Dual-clock Asynchronous FIFO with Gray-coded write pointer (`wr_ptr_gray`) and read pointer (`rd_ptr_gray`).
- **Synchronizers**: 3-stage flip-flop synchronizers with `DONT_TOUCH` and `ASYNC_REG` attributes to maximize MTBF (> 1000 years).

```
Elastic Buffer State & SKP Handling:

   Occupancy [31:0]
   32 +-----------------------+ Overflow Hazard
      |                       |
   24 +-----------------------+ HIGH WATERMARK --> If block == SKP OS:
      |                       |                    DROP (Swallow) SKP OS!
      |                       |                    wr_ptr does NOT advance.
   16 +-----------------------+ NOMINAL TARGET (Equilibrium)
      |                       |
      |                       |
    8 +-----------------------+ LOW WATERMARK  --> If block == SKP OS:
      |                       |                    DUPLICATE / INJECT SKP OS!
    0 +-----------------------+ Underflow Hazard   rd_ptr holds or injects.
```

#### 4.3 Pointer Inversion-Free Formal Guarantee
Gray-code pointers guarantee that exactly one bit changes per count step:
$$H(G(n), G(n+1)) = 1$$
Even if CDC multi-flop synchronizers experience metastability resolution on different clock edges, the sampled Gray pointer will either reflect the old value or the new value; it can never produce an invalid transition or pointer inversion.

---

### 5. TLP Boundary Parser & LCRC-32 Calculation Engine

#### 5.1 PCIe Gen3 Framing Token: STP
Data blocks contain framing tokens placed on 4-byte (DWORD) boundaries:
- **STP Token (4 bytes / 32 bits)**:
  - Byte 0: `8'hF0` (STP identifier)
  - Byte 1: `{Length[10:8], SeqNum[11:7]}`
  - Byte 2: `SeqNum[6:0], Parity`
  - Byte 3: `Length[7:0]`

#### 5.2 TLP Structure
```
+---------------+-------------------+--------------------+----------+
| STP (4 Bytes) | Header (3/4 DW)   | Payload (0-1024 DW)| LCRC (4B)|
+---------------+-------------------+--------------------+----------+
|<-- Token ---->|<---------------- Covered by LCRC-32 ----------->|
```

#### 5.3 32-bit LCRC Engine
The 32-bit Link CRC covers the Sequence Number, TLP Header, and Data Payload.
- **Polynomial**:
  $$G(x) = x^{32} + x^{26} + x^{23} + x^{22} + x^{16} + x^{12} + x^{11} + x^{10} + x^8 + x^7 + x^5 + x^4 + x^2 + x + 1$$
  Hex value: `32'h04C11DB7`.
- **Initialization**: `32'hFFFFFFFF`.
- **Final XOR**: `32'hFFFFFFFF`.
- **Residue on Error-Free Reception**: `32'hC704DD7B`.

The engine evaluates up to 128 bits (4 DWORDs) per clock cycle with DWORD-granularity byte enables for non-aligned packet boundaries.
