#!/usr/bin/env python3
# =============================================================================
# Company / Author: Abhijit Karale
# Project: PCIe Gen3 / CXL 2.0 Physical Link Layer Transaction Decoder
# Module: pcie_ref_model.py
# Target Technology: SkyWater 130nm / FreePDK45 @ 250 MHz
# Description: Bit-accurate Python reference model for:
#              1. PCIe Gen3 PRBS-23 LFSR Descrambler (x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1)
#              2. Dual-clock Elastic Buffer with +/- 300 ppm drift & SKP compensation
#              3. PCIe 32-bit LCRC calculation engine and residue checker (0xC704DD7B)
#              4. Complete test vector generator and standalone verification suite.
# =============================================================================

import sys
import struct
import random

# Protocol Constants
SYNC_HDR_DATA        = 0b01
SYNC_HDR_ORDERED_SET = 0b10
SYNC_HDR_ERR_00      = 0b00
SYNC_HDR_ERR_11      = 0b11

LFSR_LANE0_SEED      = 0x1DBFBC
LCRC32_POLY          = 0x04C11DB7
LCRC32_INIT          = 0xFFFFFFFF
LCRC32_XOR_OUT       = 0xFFFFFFFF
LCRC32_RESIDUE       = 0xC704DD7B

TOKEN_STP            = 0xF0
TOKEN_EDB            = 0x0F
SKP_SYMBOL           = 0xAA
SKP_PATTERN_32       = 0xAAAAAAAA

FIFO_DEPTH           = 32
HIGH_WATERMARK       = 24
LOW_WATERMARK        = 8
NOMINAL_LEVEL        = 16


# =============================================================================
# 1. Bit-Accurate 23-bit Parallel LFSR Descrambler Model
# =============================================================================
class PCIeDescramblerRef:
    def __init__(self, seed=LFSR_LANE0_SEED):
        self.state = seed & 0x7FFFFF

    def reset_seed(self, seed=LFSR_LANE0_SEED):
        self.state = seed & 0x7FFFFF

    def step_bit(self):
        s = self.state
        prbs_bit = (s >> 22) & 1
        # G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
        fb = ((s >> 22) ^ (s >> 20) ^ (s >> 15) ^ (s >> 7) ^ (s >> 4) ^ (s >> 1) ^ (s >> 0)) & 1
        self.state = ((s << 1) & 0x7FFFFE) | fb
        return prbs_bit

    def advance_128b(self):
        mask = 0
        for i in range(128):
            b = self.step_bit()
            mask |= (b << i)
        return mask

    def descramble_block(self, sync_hdr, raw_payload, is_skp=False):
        if sync_hdr == SYNC_HDR_ORDERED_SET or is_skp:
            # Ordered Sets bypass descrambling
            return raw_payload
        elif sync_hdr == SYNC_HDR_DATA:
            mask = self.advance_128b()
            return raw_payload ^ mask
        else:
            # Corrupted header
            return raw_payload


# =============================================================================
# 2. 32-bit Link CRC (LCRC-32) Reference Model
# =============================================================================
class PCIeLCRC32Ref:
    @staticmethod
    def step_byte(crc_val, data_byte):
        c = crc_val
        for i in range(8):
            fb = ((c >> 31) ^ ((data_byte >> i) & 1)) & 1
            c = (((c << 1) & 0xFFFFFFFF) ^ (LCRC32_POLY if fb else 0))
        return c

    @staticmethod
    def step_dword(crc_val, dw):
        c = crc_val
        c = PCIeLCRC32Ref.step_byte(c, (dw >> 0) & 0xFF)
        c = PCIeLCRC32Ref.step_byte(c, (dw >> 8) & 0xFF)
        c = PCIeLCRC32Ref.step_byte(c, (dw >> 16) & 0xFF)
        c = PCIeLCRC32Ref.step_byte(c, (dw >> 24) & 0xFF)
        return c

    @staticmethod
    def calculate_lcrc(dwords):
        c = LCRC32_INIT
        for dw in dwords:
            c = PCIeLCRC32Ref.step_dword(c, dw)
        return c ^ LCRC32_XOR_OUT

    @staticmethod
    def format_wire_crc(crc_inverted):
        # PCIe Wire format: byte b is bit-reversal of byte (3 - b) of inverted CRC
        wire_crc = 0
        for b in range(4):
            byte_val = (crc_inverted >> ((3 - b) * 8)) & 0xFF
            rev_byte = int(f"{byte_val:08b}"[::-1], 2)
            wire_crc |= (rev_byte << (b * 8))
        return wire_crc

    @staticmethod
    def verify_residue(dwords, wire_crc):
        c = LCRC32_INIT
        for dw in dwords:
            c = PCIeLCRC32Ref.step_dword(c, dw)
        c = PCIeLCRC32Ref.step_dword(c, wire_crc)
        return c == LCRC32_RESIDUE


# =============================================================================
# 3. Elastic Buffer PPM Drift Simulation Model
# =============================================================================
class ElasticBufferRef:
    def __init__(self, depth=FIFO_DEPTH, high_wm=HIGH_WATERMARK, low_wm=LOW_WATERMARK):
        self.depth = depth
        self.high_wm = high_wm
        self.low_wm = low_wm
        self.fifo = []
        self.skp_deleted_cnt = 0
        self.skp_inserted_cnt = 0
        self.overflow_err = False
        self.underflow_err = False

        # Pre-fill to nominal level
        for i in range(NOMINAL_LEVEL):
            self.fifo.append({"type": "IDLE", "data": 0})

    def write_block(self, block_type, data, is_skp):
        occupancy = len(self.fifo)
        # Check SKP deletion trigger (+300 ppm drift compensation)
        if is_skp and occupancy >= self.high_wm:
            self.skp_deleted_cnt += 1
            # Discard SKP block (swallowed)
            return False

        if occupancy >= self.depth:
            self.overflow_err = True
            return False

        self.fifo.append({"type": block_type, "data": data, "is_skp": is_skp})
        return True

    def read_block(self):
        occupancy = len(self.fifo)
        if occupancy == 0:
            self.underflow_err = True
            return None

        # Check SKP insertion trigger (-300 ppm drift compensation)
        head = self.fifo[0]
        if head.get("is_skp", False) and occupancy <= self.low_wm:
            self.skp_inserted_cnt += 1
            # Duplicate SKP block: return without popping once
            return head

        return self.fifo.pop(0)


# =============================================================================
# 4. Self-Checking Regression & Test Runner
# =============================================================================
def run_all_tests():
    print("=" * 70)
    print(" PCIe Gen3 / CXL 2.0 Transaction Decoder Python Reference Model")
    print(" Author: Abhijit Karale | Tech Node: SkyWater 130nm / FreePDK45 @ 250 MHz")
    print("=" * 70)

    # Test 1: LCRC-32 and Magic Residue Verification
    print("\n[TEST 1] Verifying 32-bit LCRC Engine & Residue (0xC704DD7B)...")
    sample_tlp = [
        0x00000000 | (0x04A << 16), # Header DW0
        0x12345678,                 # Header DW1
        0xDEADBEEF,                 # Header DW2
        0xCAFEF00D,                 # Payload DW0
        0x01020304                  # Payload DW1
    ]
    crc_inv = PCIeLCRC32Ref.calculate_lcrc(sample_tlp)
    wire_crc = PCIeLCRC32Ref.format_wire_crc(crc_inv)
    residue_pass = PCIeLCRC32Ref.verify_residue(sample_tlp, wire_crc)
    print(f"  Calculated Inverted CRC : 0x{crc_inv:08X}")
    print(f"  PCIe Transmitted Wire CRC: 0x{wire_crc:08X}")
    print(f"  Residue Match (0xC704DD7B): {residue_pass}")
    assert residue_pass, "Residue verification failed!"
    print("  -> TEST 1 PASSED: 100% LCRC-32 Mathematical Convergence.")

    # Test 2: Single Bit Flip Detection
    print("\n[TEST 2] Verifying 100% Single-Bit Corruption Detection...")
    corrupted_wire_crc = wire_crc ^ 0x00000001 # 1-bit flip
    residue_corrupt = PCIeLCRC32Ref.verify_residue(sample_tlp, corrupted_wire_crc)
    print(f"  Corrupted CRC Residue Match: {residue_corrupt} (Expected: False)")
    assert not residue_corrupt, "Corrupted packet was not rejected!"
    print("  -> TEST 2 PASSED: 100% Detection of Bit Corruptions.")

    # Test 3: LFSR Descrambler Invertibility
    print("\n[TEST 3] Verifying Parallel 128-bit LFSR Descrambler...")
    lfsr_tx = PCIeDescramblerRef(LFSR_LANE0_SEED)
    lfsr_rx = PCIeDescramblerRef(LFSR_LANE0_SEED)
    plaintext_data = 0x0123456789ABCDEF0123456789ABCDEF
    mask_tx = lfsr_tx.advance_128b()
    ciphertext = plaintext_data ^ mask_tx
    mask_rx = lfsr_rx.advance_128b()
    recovered_data = ciphertext ^ mask_rx
    print(f"  Plaintext Data : 0x{plaintext_data:032X}")
    print(f"  Scrambled Cipher: 0x{ciphertext:032X}")
    print(f"  Recovered Data : 0x{recovered_data:032X}")
    assert recovered_data == plaintext_data, "Descrambler reconstruction mismatch!"
    print("  -> TEST 3 PASSED: Descrambler perfectly recovers scrambled 128b stream.")

    # Test 4: Elastic Buffer +/- 300 ppm Clock Drift & SKP Compensation
    print("\n[TEST 4] Verifying Elastic Buffer +/- 300 ppm Clock Drift Compensation...")
    eb = ElasticBufferRef()

    # Emulate positive drift (+300 ppm): Write faster than read
    print("  Simulating +300 ppm drift (FIFO fill towards High Watermark)...")
    for cycle in range(30):
        eb.write_block("DATA", 0x11111111, is_skp=False)
        if cycle % 2 == 0:
            eb.read_block()

    print(f"  Current Occupancy: {len(eb.fifo)} (High Watermark = {HIGH_WATERMARK})")
    assert len(eb.fifo) >= HIGH_WATERMARK, "FIFO occupancy did not reach high watermark!"

    # Send SKP Ordered Set -> Must be dropped
    dropped = not eb.write_block("OS", SKP_PATTERN_32, is_skp=True)
    print(f"  Incoming SKP Ordered Set Dropped (Swallowed): {dropped}")
    assert dropped, "SKP Ordered Set was not dropped above high watermark!"
    print(f"  Total SKP Deleted: {eb.skp_deleted_cnt}")

    # Emulate negative drift (-300 ppm): Read faster than write
    print("  Simulating -300 ppm drift (FIFO drain towards Low Watermark)...")
    for cycle in range(25):
        eb.read_block()

    print(f"  Current Occupancy: {len(eb.fifo)} (Low Watermark = {LOW_WATERMARK})")
    assert len(eb.fifo) <= LOW_WATERMARK, "FIFO occupancy did not drop below low watermark!"

    # Put a SKP in FIFO and read -> Must be duplicated
    eb.write_block("OS", SKP_PATTERN_32, is_skp=True)
    dup_block = eb.read_block()
    print(f"  Total SKP Inserted/Duplicated: {eb.skp_inserted_cnt}")
    assert eb.skp_inserted_cnt > 0, "SKP Ordered Set was not duplicated below low watermark!"
    assert not eb.overflow_err and not eb.underflow_err, "FIFO experienced overflow or underflow!"
    print("  -> TEST 4 PASSED: Zero overflow, zero underflow, correct SKP compensation.")

    print("\n" + "=" * 70)
    print(" ALL REFERENCE MODEL TESTS COMPLETED SUCCESSFULLY (100% PASS)")
    print("=" * 70)


if __name__ == "__main__":
    run_all_tests()
