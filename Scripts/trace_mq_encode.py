#!/usr/bin/env python3
"""
Trace MQ encoding of the HL code block to find the exact byte where
our encoder diverges from the standard.
"""

# MQ State Table (ISO 15444-1 Table C.2)
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


class MQEncoder:
    def __init__(self):
        self.c = 0
        self.a = 0x8000
        self.ct = 12
        self.buffer = -1
        self.output = []
        self.op_count = 0
        
        # 19 contexts  
        self.ctx_state = [0] * 19
        self.ctx_mps = [False] * 19
        self.ctx_state[0] = 4    # ZC
        self.ctx_state[17] = 3   # AGG
        self.ctx_state[18] = 46  # UNI
    
    def encode(self, symbol, ctx_idx, label=""):
        self.op_count += 1
        state_idx = self.ctx_state[ctx_idx]
        mps = self.ctx_mps[ctx_idx]
        qe, next_mps_st, next_lps_st, switch = MQ_STATES[state_idx]
        
        pre_a = self.a
        pre_c = self.c
        
        self.a -= qe
        
        if symbol == mps:
            # CODEMPS
            if (self.a & 0x8000) == 0:
                if self.a < qe:
                    # Conditional exchange
                    self.a = qe
                else:
                    self.c += qe
                self.ctx_state[ctx_idx] = next_mps_st
                self._renormalize()
            else:
                self.c += qe
        else:
            # CODELPS
            if self.a < qe:
                # Conditional exchange
                self.c += qe
            else:
                self.a = qe
            if switch:
                self.ctx_mps[ctx_idx] = not mps
            self.ctx_state[ctx_idx] = next_lps_st
            self._renormalize()
        
        post_a = self.a
        post_c = self.c
        print(f"  ENC#{self.op_count}: ctx={ctx_idx} st={state_idx} qe=0x{qe:04x} sym={symbol} mps={mps} "
              f"A:0x{pre_a:04x}->0x{post_a:04x} C:0x{pre_c:08x}->0x{post_c:08x} buf={self.buffer} out={len(self.output)} {label}")
    
    def _emit_byte(self):
        if self.buffer >= 0:
            if self.buffer == 0xFF:
                self.output.append(0xFF)
                self.buffer = int((self.c >> 20) & 0xFF)
                self.c &= 0x000FFFFF
                self.ct = 7
                print(f"    BYTEOUT(0xFF-mode): emit 0xFF, buf=0x{self.buffer:02x}, ct=7")
            else:
                self.buffer += int(self.c >> 27)
                self.c &= 0x07FFFFFF
                self.output.append(self.buffer & 0xFF)
                self.buffer = int((self.c >> 19) & 0xFF)
                self.c &= 0x0007FFFF
                self.ct = 8
                print(f"    BYTEOUT: emit 0x{self.output[-1]:02x}, buf=0x{self.buffer:02x}, ct={self.ct}")
        else:
            # First byte
            self.c &= 0x07FFFFFF
            self.buffer = int((self.c >> 19) & 0xFF)
            self.c &= 0x0007FFFF
            self.ct = 8
            print(f"    BYTEOUT(first): buf=0x{self.buffer:02x}, ct=8")
    
    def _renormalize(self):
        while self.a < 0x8000:
            self.a <<= 1
            self.c <<= 1
            self.ct -= 1
            if self.ct == 0:
                self._emit_byte()
    
    def finish(self):
        """FLUSH (default termination)"""
        # SETBITS
        temp_c = self.c + self.a
        self.c = self.c | 0x0000FFFF
        if self.c >= temp_c:
            self.c -= 0x8000
        
        print(f"  FLUSH: after SETBITS C=0x{self.c:08x}")
        
        # Two BYTEOUT
        self.c <<= self.ct
        self._emit_byte()
        self.c <<= self.ct
        self._emit_byte()
        
        # Emit final buffer
        if self.buffer >= 0 and self.buffer != 0xFF:
            self.output.append(self.buffer & 0xFF)
            print(f"    FLUSH: emit final buf 0x{self.buffer:02x}")
        
        # Drop trailing 0xFF
        while self.output and self.output[-1] == 0xFF:
            self.output.pop()
            print(f"    FLUSH: drop trailing 0xFF")
        
        return bytes(self.output)


def encode_hl_block():
    """Encode the HL code block [25, 332, 25, 332] with EBCOT."""
    # Block: 2x2, HL subband
    # Coefficients (row-major, idx = y*w+x):
    #   (0,0)=25  (1,0)=332
    #   (0,1)=25  (1,1)=332
    # All positive (signs = False)
    # Kb=12, zeroBitPlanes = 12 - 9 = 3 (max=332, activeBitPlanes=9)
    
    coeffs = [25, 332, 25, 332]  # [idx0, idx1, idx2, idx3]
    mags = [abs(c) for c in coeffs]
    signs = [c < 0 for c in coeffs]  # all False
    w, h = 2, 2
    active_planes = 9  # floor(log2(332))+1 = 9
    
    # significance/state tracking
    significant = [False] * 4
    coded_this_pass = [False] * 4
    first_refine = [False] * 4
    
    enc = MQEncoder()
    pass_count = 0
    
    print(f"=== ENCODING HL CODE BLOCK: {mags} ===\n")
    
    for bp in range(active_planes - 1, -1, -1):
        bit_mask = 1 << bp
        is_first_bp = (bp == active_planes - 1)
        
        # SPP (skip for first BP)
        if not is_first_bp:
            print(f"\n--- SPP bp={bp} pass={pass_count} ---")
            for x in range(w):
                for y in range(h):
                    idx = y * w + x
                    if significant[idx] or coded_this_pass[idx]:
                        continue
                    # Check neighbors  
                    has_sig_nb = False
                    nb_ctx = get_hl_sig_context(x, y, w, h, significant)
                    has_any = any_significant_neighbor(x, y, w, h, significant)
                    if not has_any:
                        continue
                    is_sig = (mags[idx] & bit_mask) != 0
                    enc.encode(is_sig, nb_ctx, f"SPP({x},{y})")
                    if is_sig:
                        # Sign
                        sctx, xor_bit = get_sign_context(x, y, w, h, significant, signs)
                        coded_sign = signs[idx] != xor_bit
                        enc.encode(coded_sign, sctx, f"SPP_SIGN({x},{y})")
                        significant[idx] = True
                    coded_this_pass[idx] = True
            pass_count += 1
        
        # MRP (skip for first BP)
        if not is_first_bp:
            print(f"\n--- MRP bp={bp} pass={pass_count} ---")
            for x in range(w):
                for y in range(h):
                    idx = y * w + x
                    if not significant[idx] or coded_this_pass[idx]:
                        continue
                    is_first_ref = not first_refine[idx]
                    has_sig = any_significant_neighbor(x, y, w, h, significant)
                    ctx = 14 if is_first_ref and not has_sig else (15 if is_first_ref else 16)
                    bit = (mags[idx] & bit_mask) != 0
                    enc.encode(bit, ctx, f"MRP({x},{y})")
                    first_refine[idx] = True
                    coded_this_pass[idx] = True
            pass_count += 1
        
        # CUP
        print(f"\n--- CUP bp={bp} pass={pass_count} ---")
        for x in range(w):
            # No RLC for 2-high blocks
            for y in range(h):
                idx = y * w + x
                if coded_this_pass[idx] or significant[idx]:
                    print(f"  CUP({x},{y}) skip")
                    continue
                nb_ctx = get_hl_sig_context(x, y, w, h, significant)
                is_sig = (mags[idx] & bit_mask) != 0
                enc.encode(is_sig, nb_ctx, f"CUP({x},{y})")
                if is_sig:
                    sctx, xor_bit = get_sign_context(x, y, w, h, significant, signs)
                    coded_sign = signs[idx] != xor_bit
                    enc.encode(coded_sign, sctx, f"CUP_SIGN({x},{y})")
                    significant[idx] = True
                coded_this_pass[idx] = True
        pass_count += 1
        
        # Clear flag
        coded_this_pass = [False] * 4
    
    result = enc.finish()
    print(f"\n=== ENCODED: {result.hex()} ({len(result)} bytes) ===")
    print(f"=== EXPECTED: 0cff5ebc9332 (6 bytes) ===")
    return result


def any_significant_neighbor(x, y, w, h, significant):
    for dx, dy in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]:
        nx, ny = x+dx, y+dy
        if 0 <= nx < w and 0 <= ny < h:
            if significant[ny*w+nx]:
                return True
    return False


def get_hl_sig_context(x, y, w, h, significant):
    """HL zero-coding context."""
    hc = vc = dc = 0
    # Horizontal
    if x > 0 and significant[y*w+(x-1)]: hc += 1
    if x < w-1 and significant[y*w+(x+1)]: hc += 1
    # Vertical
    if y > 0 and significant[(y-1)*w+x]: vc += 1
    if y < h-1 and significant[(y+1)*w+x]: vc += 1
    # Diagonal
    for dx, dy in [(-1,-1),(1,-1),(-1,1),(1,1)]:
        nx, ny = x+dx, y+dy
        if 0 <= nx < w and 0 <= ny < h and significant[ny*w+nx]: dc += 1
    
    if vc >= 2: return 8
    elif vc == 1:
        if hc >= 1: return 7
        elif dc >= 1: return 6
        else: return 5
    else:
        if hc >= 2: return 4
        elif hc == 1: return 3
        elif dc >= 2: return 2
        elif dc == 1: return 1
        else: return 0


def get_sign_context(x, y, w, h, significant, signs):
    """Sign coding context."""
    h_pos = h_neg = v_pos = v_neg = 0
    if x > 0 and significant[y*w+(x-1)]:
        if signs[y*w+(x-1)]: h_neg += 1
        else: h_pos += 1
    if x < w-1 and significant[y*w+(x+1)]:
        if signs[y*w+(x+1)]: h_neg += 1
        else: h_pos += 1
    if y > 0 and significant[(y-1)*w+x]:
        if signs[(y-1)*w+x]: v_neg += 1
        else: v_pos += 1
    if y < h-1 and significant[(y+1)*w+x]:
        if signs[(y+1)*w+x]: v_neg += 1
        else: v_pos += 1
    
    if h_pos > 0 and h_neg > 0: hs = 0
    elif h_pos > 0: hs = 1
    elif h_neg > 0: hs = -1
    else: hs = 0
    
    if v_pos > 0 and v_neg > 0: vs = 0
    elif v_pos > 0: vs = 1
    elif v_neg > 0: vs = -1
    else: vs = 0
    
    hc = 0 if hs == 0 else (1 if hs > 0 else -1)
    vc = 0 if vs == 0 else (1 if vs > 0 else -1)
    xor_bit = (hc < 0) or (hc == 0 and vc < 0)
    if hc < 0: hc = -hc; vc = -vc
    if hc == 0 and vc < 0: vc = -vc
    
    if hc == 0:
        ctx = 9 if vc == 0 else 10
    else:
        ctx = 13 if vc > 0 else (11 if vc < 0 else 12)
    
    return ctx, xor_bit


if __name__ == '__main__':
    encode_hl_block()
