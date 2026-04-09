#!/usr/bin/env python3
"""
Reference EBCOT Tier 1 decoder matching ISO 15444-1 / OpenJPEG.
Decodes individual code blocks from raw MQ-coded data.
"""

import sys

# ============================================================
# MQ State Table (ISO 15444-1 Table C.2)
# Each entry: (qe, next_mps, next_lps, switch_mps)
# ============================================================
MQ_STATES = [
    (0x5601, 1, 1, True),    # 0
    (0x3401, 2, 6, False),   # 1
    (0x1801, 3, 9, False),   # 2
    (0x0AC1, 4, 12, False),  # 3
    (0x0521, 5, 29, False),  # 4
    (0x0221, 38, 33, False), # 5
    (0x5601, 7, 6, True),    # 6
    (0x5401, 8, 14, False),  # 7
    (0x4801, 9, 14, False),  # 8
    (0x3801, 10, 14, False), # 9
    (0x3001, 11, 17, False), # 10
    (0x2401, 12, 18, False), # 11
    (0x1C01, 13, 20, False), # 12
    (0x1601, 29, 21, False), # 13
    (0x5601, 15, 14, True),  # 14
    (0x5401, 16, 14, False), # 15
    (0x5101, 17, 15, False), # 16
    (0x4801, 18, 16, False), # 17
    (0x3801, 19, 17, False), # 18
    (0x3401, 20, 18, False), # 19
    (0x3001, 21, 19, False), # 20
    (0x2801, 22, 19, False), # 21
    (0x2401, 23, 20, False), # 22
    (0x2201, 24, 21, False), # 23
    (0x1C01, 25, 22, False), # 24
    (0x1801, 26, 23, False), # 25
    (0x1601, 27, 24, False), # 26
    (0x1401, 28, 25, False), # 27
    (0x1201, 29, 26, False), # 28
    (0x1101, 30, 27, False), # 29
    (0x0AC1, 31, 28, False), # 30
    (0x09C1, 32, 29, False), # 31
    (0x08A1, 33, 30, False), # 32
    (0x0521, 34, 31, False), # 33
    (0x0441, 35, 32, False), # 34
    (0x02A1, 36, 33, False), # 35
    (0x0221, 37, 34, False), # 36
    (0x0141, 38, 35, False), # 37
    (0x0111, 39, 36, False), # 38
    (0x0085, 40, 37, False), # 39
    (0x0049, 41, 38, False), # 40
    (0x0025, 42, 39, False), # 41
    (0x0015, 43, 40, False), # 42
    (0x0009, 44, 41, False), # 43
    (0x0005, 45, 42, False), # 44
    (0x0001, 45, 43, False), # 45
    (0x5601, 46, 46, False), # 46 (uniform)
]

# ============================================================
# MQ Decoder
# ============================================================
class MQDecoder:
    def __init__(self, data):
        self.data = list(data) + [0xFF]*4  # pad for safety
        self.pos = 0
        self.c = 0
        self.a = 0
        self.ct = 0
        self.buffer = 0
        self.op_count = 0
        
        # 19 contexts: (state_index, mps_symbol)
        self.ctx_state = [0] * 19
        self.ctx_mps = [False] * 19
        
        # Initial states per OPJ
        self.ctx_state[0] = 4     # ZC context 0
        self.ctx_mps[0] = False
        self.ctx_state[17] = 3    # AGG (run-length)
        self.ctx_mps[17] = False
        self.ctx_state[18] = 46   # UNI (uniform)
        self.ctx_mps[18] = False
        
        self._init_dec()
    
    def _read_byte(self):
        if self.pos < len(self.data):
            b = self.data[self.pos]
            self.pos += 1
            return b
        return 0xFF
    
    def _bytein(self):
        if self.buffer == 0xFF:
            next_b = self._read_byte()
            if next_b > 0x8F:
                # Marker - don't consume
                self.pos -= 1
                self.c += 0xFF00
                self.ct = 8
            else:
                self.buffer = next_b
                self.c += next_b << 9
                self.ct = 7
        else:
            self.buffer = self._read_byte()
            self.c += self.buffer << 8
            self.ct = 8
    
    def _init_dec(self):
        # INITDEC procedure
        self.buffer = self._read_byte()
        self.c = self.buffer << 16
        self._bytein()
        self.c <<= 7
        self.ct -= 7
        self.a = 0x8000
    
    def _renormalize(self):
        while self.a < 0x8000:
            if self.ct == 0:
                self._bytein()
            self.a <<= 1
            self.c <<= 1
            self.ct -= 1
    
    def decode(self, ctx_idx):
        """Decode one symbol using the given context index."""
        self.op_count += 1
        
        state_idx = self.ctx_state[ctx_idx]
        mps = self.ctx_mps[ctx_idx]
        qe, next_mps_st, next_lps_st, switch = MQ_STATES[state_idx]
        
        self.a -= qe
        
        # Check which sub-interval the code value falls in
        # C register high 16 bits
        chigh = (self.c >> 16) & 0xFFFF
        
        if chigh < qe:
            # LPS exchange region
            if self.a < qe:
                # Conditional exchange: A < Qe, so swap
                self.a = qe  # A = Qe in BOTH branches per ISO & OPJ
                symbol = mps
                self.ctx_state[ctx_idx] = next_mps_st
            else:
                symbol = not mps
                self.a = qe
                if switch:
                    self.ctx_mps[ctx_idx] = not mps
                self.ctx_state[ctx_idx] = next_lps_st
            self._renormalize()
        else:
            # MPS exchange region
            self.c -= qe << 16
            if (self.a & 0x8000) == 0:
                # Need renormalization
                if self.a < qe:
                    # Conditional exchange
                    symbol = not mps
                    if switch:
                        self.ctx_mps[ctx_idx] = not mps
                    self.ctx_state[ctx_idx] = next_lps_st
                else:
                    symbol = mps
                    self.ctx_state[ctx_idx] = next_mps_st
                self._renormalize()
            else:
                symbol = mps
        
        return bool(symbol)


# ============================================================
# Context Modeling for EBCOT
# ============================================================

def get_neighbors(x, y, w, h, significant, signs):
    """Get neighbor contribution for context modeling.
    Returns (h_count, v_count, d_count, h_sign, v_sign)
    """
    hc = 0  # horizontal significant count
    vc = 0  # vertical significant count
    dc = 0  # diagonal significant count
    h_pos = 0
    h_neg = 0
    v_pos = 0
    v_neg = 0
    
    # Left (x-1, y)
    if x > 0:
        idx = y * w + (x - 1)
        if significant[idx]:
            hc += 1
            if signs[idx]: h_neg += 1
            else: h_pos += 1
    
    # Right (x+1, y)
    if x < w - 1:
        idx = y * w + (x + 1)
        if significant[idx]:
            hc += 1
            if signs[idx]: h_neg += 1
            else: h_pos += 1
    
    # Top (x, y-1)
    if y > 0:
        idx = (y - 1) * w + x
        if significant[idx]:
            vc += 1
            if signs[idx]: v_neg += 1
            else: v_pos += 1
    
    # Bottom (x, y+1)
    if y < h - 1:
        idx = (y + 1) * w + x
        if significant[idx]:
            vc += 1
            if signs[idx]: v_neg += 1
            else: v_pos += 1
    
    # Diagonals
    for dx, dy in [(-1,-1), (1,-1), (-1,1), (1,1)]:
        nx, ny = x + dx, y + dy
        if 0 <= nx < w and 0 <= ny < h:
            idx = ny * w + nx
            if significant[idx]:
                dc += 1
    
    # Compute sign contributions
    if h_pos > 0 and h_neg > 0:
        h_sign = 0  # mixed
    elif h_pos > 0:
        h_sign = 1
    elif h_neg > 0:
        h_sign = -1
    else:
        h_sign = 0
    
    if v_pos > 0 and v_neg > 0:
        v_sign = 0
    elif v_pos > 0:
        v_sign = 1
    elif v_neg > 0:
        v_sign = -1
    else:
        v_sign = 0
    
    return hc, vc, dc, h_sign, v_sign


def significance_context_HL(h, v, d):
    """Zero-coding context for HL subband (ISO 15444-1 Table D.1)."""
    if v >= 2:
        return 8
    elif v == 1:
        if h >= 1:
            return 7
        elif d >= 1:
            return 6
        else:
            return 5
    else:  # v == 0
        if h >= 2:
            return 4
        elif h == 1:
            return 3
        elif d >= 2:
            return 2
        elif d == 1:
            return 1
        else:
            return 0


def significance_context_LH(h, v, d):
    """Zero-coding context for LL/LH subband (ISO 15444-1 Table D.1)."""
    if h >= 2:
        return 8
    elif h == 1:
        if v >= 1:
            return 7
        elif d >= 1:
            return 6
        else:
            return 5
    else:  # h == 0
        if v >= 2:
            return 4
        elif v == 1:
            return 3
        elif d >= 2:
            return 2
        elif d == 1:
            return 1
        else:
            return 0


def sign_context(h_sign, v_sign):
    """Sign coding context (ISO 15444-1 Table D.3).
    Returns (context_index, xor_bit)
    """
    hc = 0 if h_sign == 0 else (1 if h_sign > 0 else -1)
    vc = 0 if v_sign == 0 else (1 if v_sign > 0 else -1)
    
    # XOR prediction
    xor_bit = (hc < 0) or (hc == 0 and vc < 0)
    
    # Canonicalize: flip so hc >= 0
    if hc < 0:
        hc = -hc
        vc = -vc
    if hc == 0 and vc < 0:
        vc = -vc
    
    # Map to context
    if hc == 0:
        if vc == 0:
            ctx = 9   # both zero
        else:
            ctx = 10  # h=0, v nonzero
    else:
        if vc > 0:
            ctx = 13  # same sign
        elif vc < 0:
            ctx = 11  # opposite sign
        else:
            ctx = 12  # h nonzero, v=0
    
    return ctx, xor_bit


def mag_refinement_context(first_refinement, has_sig_neighbors):
    """Magnitude refinement context (ISO 15444-1 Table D.4)."""
    if not first_refinement:
        return 16  # subsequent refinement
    elif has_sig_neighbors:
        return 15  # first with neighbors
    else:
        return 14  # first without neighbors


# ============================================================
# T1 Decoder
# ============================================================

def decode_code_block(data, w, h, active_planes, subband_type='hl'):
    """Decode an EBCOT code block.
    
    Args:
        data: raw MQ-coded bytes
        w, h: code block dimensions
        active_planes: number of active bit planes (Mb - zbp)
        subband_type: 'hl', 'lh', 'll', or 'hh'
    
    Returns:
        List of decoded signed coefficients (row-major)
    """
    sig_ctx_fn = {
        'hl': significance_context_HL,
        'lh': significance_context_LH,
        'll': significance_context_LH,
        'hh': None  # would need its own function
    }[subband_type]
    
    mqd = MQDecoder(data)
    
    n = w * h
    magnitudes = [0] * n
    signs = [False] * n  # True = negative
    significant = [False] * n
    coded_this_pass = [False] * n
    first_refine = [False] * n  # True once first refinement done
    
    stripe_height = 4
    pass_count = 0
    
    print(f"=== T1 Decode: {w}x{h}, {active_planes} active planes, {subband_type} ===")
    print(f"Data hex: {bytes(data).hex()}")
    
    for bp in range(active_planes - 1, -1, -1):
        bit_value = 1 << bp
        is_first_bp = (bp == active_planes - 1)
        
        # === Significance Propagation Pass (skip for first bit plane) ===
        if not is_first_bp:
            print(f"\n--- SPP bit_plane={bp} pass={pass_count} ---")
            for stripe_y in range(0, h, stripe_height):
                stripe_end = min(stripe_y + stripe_height, h)
                for x in range(w):
                    for y in range(stripe_y, stripe_end):
                        idx = y * w + x
                        if significant[idx] or coded_this_pass[idx]:
                            continue
                        
                        hc, vc, dc, hs, vs = get_neighbors(x, y, w, h, significant, signs)
                        has_any = (hc + vc + dc) > 0
                        
                        if not has_any:
                            continue
                        
                        ctx = sig_ctx_fn(hc, vc, dc)
                        is_sig = mqd.decode(ctx)
                        print(f"  SPP ({x},{y}) ctx={ctx} -> sig={is_sig}")
                        
                        if is_sig:
                            # Decode sign
                            sctx, xor_bit = sign_context(hs, vs)
                            coded_sign = mqd.decode(sctx)
                            actual_sign = coded_sign != xor_bit
                            signs[idx] = actual_sign
                            magnitudes[idx] |= bit_value
                            significant[idx] = True
                            print(f"    SIGN ({x},{y}) ctx={sctx} xor={xor_bit} coded={coded_sign} -> neg={actual_sign}")
                        
                        coded_this_pass[idx] = True
            
            pass_count += 1
        
        # === Magnitude Refinement Pass (skip for first bit plane) ===
        if not is_first_bp:
            print(f"\n--- MRP bit_plane={bp} pass={pass_count} ---")
            for stripe_y in range(0, h, stripe_height):
                stripe_end = min(stripe_y + stripe_height, h)
                for x in range(w):
                    for y in range(stripe_y, stripe_end):
                        idx = y * w + x
                        if not significant[idx]:
                            continue
                        if coded_this_pass[idx]:
                            continue
                        
                        hc, vc, dc, _, _ = get_neighbors(x, y, w, h, significant, signs)
                        has_sig = (hc + vc + dc) > 0
                        is_first_ref = not first_refine[idx]
                        
                        ctx = mag_refinement_context(is_first_ref, has_sig)
                        bit = mqd.decode(ctx)
                        if bit:
                            magnitudes[idx] |= bit_value
                        print(f"  MRP ({x},{y}) ctx={ctx} first_ref={is_first_ref} sig_nb={has_sig} -> bit={bit}")
                        
                        first_refine[idx] = True
                        coded_this_pass[idx] = True
            
            pass_count += 1
        
        # === Cleanup Pass ===
        print(f"\n--- CUP bit_plane={bp} pass={pass_count} ---")
        for stripe_y in range(0, h, stripe_height):
            stripe_end = min(stripe_y + stripe_height, h)
            
            for x in range(w):
                # Check RLC eligibility
                rlc_eligible = (stripe_end - stripe_y == 4)
                if rlc_eligible:
                    for y_check in range(stripe_y, stripe_end):
                        idx_check = y_check * w + x
                        if significant[idx_check] or coded_this_pass[idx_check]:
                            rlc_eligible = False
                            break
                        hc, vc, dc, _, _ = get_neighbors(x, y_check, w, h, significant, signs)
                        if (hc + vc + dc) > 0:
                            rlc_eligible = False
                            break
                
                if rlc_eligible:
                    # Decode RLC
                    has_sig = mqd.decode(17)  # runLength context
                    print(f"  RLC x={x} -> has_sig={has_sig}")
                    
                    if not has_sig:
                        for y in range(stripe_y, stripe_end):
                            coded_this_pass[y * w + x] = True
                        continue
                    
                    # Decode position (2 bits via uniform context)
                    pos_msb = mqd.decode(18)
                    pos_lsb = mqd.decode(18)
                    first_sig_pos = (int(pos_msb) << 1) | int(pos_lsb)
                    print(f"    RLC pos={first_sig_pos}")
                    
                    # Mark preceding as coded
                    for i in range(first_sig_pos):
                        coded_this_pass[(stripe_y + i) * w + x] = True
                    
                    # Decode sign of first significant
                    first_y = stripe_y + first_sig_pos
                    first_idx = first_y * w + x
                    hc, vc, dc, hs, vs = get_neighbors(x, first_y, w, h, significant, signs)
                    sctx, xor_bit = sign_context(hs, vs)
                    coded_sign = mqd.decode(sctx)
                    actual_sign = coded_sign != xor_bit
                    signs[first_idx] = actual_sign
                    magnitudes[first_idx] |= bit_value
                    significant[first_idx] = True
                    coded_this_pass[first_idx] = True
                    print(f"    RLC sign ({x},{first_y}) ctx={sctx} -> neg={actual_sign}")
                    
                    # Process remaining after first significant
                    for y in range(first_y + 1, stripe_end):
                        idx = y * w + x
                        if significant[idx] or coded_this_pass[idx]:
                            continue
                        
                        hc, vc, dc, hs, vs = get_neighbors(x, y, w, h, significant, signs)
                        ctx = sig_ctx_fn(hc, vc, dc)
                        is_sig = mqd.decode(ctx)
                        print(f"    RLC-rem ({x},{y}) ctx={ctx} -> sig={is_sig}")
                        
                        if is_sig:
                            sctx, xor_bit = sign_context(hs, vs)
                            coded_sign = mqd.decode(sctx)
                            actual_sign = coded_sign != xor_bit
                            signs[idx] = actual_sign
                            magnitudes[idx] |= bit_value
                            significant[idx] = True
                            print(f"      SIGN ({x},{y}) ctx={sctx} -> neg={actual_sign}")
                        
                        coded_this_pass[idx] = True
                else:
                    # No RLC: process each coefficient individually
                    for y in range(stripe_y, stripe_end):
                        idx = y * w + x
                        
                        if coded_this_pass[idx] or significant[idx]:
                            print(f"  CUP ({x},{y}) skip (coded/sig)")
                            continue
                        
                        hc, vc, dc, hs, vs = get_neighbors(x, y, w, h, significant, signs)
                        ctx = sig_ctx_fn(hc, vc, dc)
                        is_sig = mqd.decode(ctx)
                        print(f"  CUP ({x},{y}) ctx={ctx} h={hc},v={vc},d={dc} -> sig={is_sig}")
                        
                        if is_sig:
                            sctx, xor_bit = sign_context(hs, vs)
                            coded_sign = mqd.decode(sctx)
                            actual_sign = coded_sign != xor_bit
                            signs[idx] = actual_sign
                            magnitudes[idx] |= bit_value
                            significant[idx] = True
                            print(f"    SIGN ({x},{y}) ctx={sctx} xor={xor_bit} coded={coded_sign} -> neg={actual_sign}")
                        
                        coded_this_pass[idx] = True
        
        pass_count += 1
        
        # Clear coded_this_pass
        coded_this_pass = [False] * n
    
    # Reconstruct signed coefficients
    coeffs = []
    for i in range(n):
        val = magnitudes[i]
        if signs[i]:
            val = -val
        coeffs.append(val)
    
    print(f"\n=== RESULT ===")
    print(f"Magnitudes: {magnitudes}")
    print(f"Signs (neg): {signs}")
    print(f"Coefficients: {coeffs}")
    print(f"MQ ops: {mqd.op_count}")
    
    return coeffs


# ============================================================
# Main
# ============================================================
if __name__ == '__main__':
    # Read our tiny_gray.j2k and decode the HL code block
    with open('/tmp/tiny_gray_fixed.j2k', 'rb') as f:
        file_data = f.read()
    
    sod = file_data.index(b'\xff\x93')
    pkt_data = file_data[sod+2:]
    if pkt_data[-2:] == b'\xff\xd9':
        pkt_data = pkt_data[:-2]
    
    print(f"Total packet data: {len(pkt_data)} bytes = {pkt_data.hex()}")
    
    # Parse packet 0 (R0, LL): header then data
    # From earlier analysis: LL header = 3 bytes, LL data = 6 bytes
    # Parse packet 1 (R1, HL + LH + HH): header then data
    
    # LL data starts at byte 3, length 6
    ll_data = pkt_data[3:9]
    
    # HL data starts at byte 13, length 6
    hl_data = pkt_data[13:19]
    
    print(f"\n{'='*60}")
    print(f"LL code block data: {ll_data.hex()}")
    print(f"HL code block data: {hl_data.hex()}")
    
    # Decode HL code block (2x2, HL subband, 9 active planes)
    print(f"\n{'='*60}")
    print("DECODING HL CODE BLOCK")
    print(f"{'='*60}")
    hl_coeffs = decode_code_block(list(hl_data), 2, 2, 9, 'hl')
    
    # Decode LL code block (2x2, LL subband, 9 active planes)
    print(f"\n{'='*60}")
    print("DECODING LL CODE BLOCK")
    print(f"{'='*60}")
    ll_coeffs = decode_code_block(list(ll_data), 2, 2, 9, 'll')
