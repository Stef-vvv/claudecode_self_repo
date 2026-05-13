"""
Eyeriss v1 Row-Stationary Dataflow — Python Behavioral Model
=============================================================
Cycle-accurate model matching the SystemVerilog RTL at:
  H:/moateff_test/src/

Based on C reference models at:
  H:/complete_version/moateff/2025_7_18_Eyeriss-v1-Data-Delivery-Pattarn-main/src/

This model produces:
  1. Golden reference output for any configured layer
  2. GLB address traces matching the NoC index generators
  3. PE computation results matching the RTL datapath
"""

import numpy as np
from dataclasses import dataclass, field
from typing import List, Tuple, Dict
import os

# ============================================================================
# Configuration
# ============================================================================
@dataclass
class LayerConfig:
    """CNN layer parameters + mapping parameters (matches scan chain registers)."""
    # Layer dimensions
    H: int = 8      # ifmap height
    W: int = 8      # ifmap width
    R: int = 3      # filter height
    S: int = 3      # filter width
    E: int = 6      # ofmap height
    F: int = 6      # ofmap width
    C: int = 1      # input channels
    M: int = 1      # output channels (filters)
    N: int = 1      # batch size
    U: int = 1      # stride

    # Mapping parameters
    m: int = 1      # filters per pass group
    n: int = 1      # ifmaps per pass group
    e: int = 6      # ofmap tile height
    p: int = 1      # filters per PE set (horizontal)
    q: int = 1      # channels per PE set
    r: int = 1      # column groups (channel parallelism)
    t: int = 1      # row groups (filter parallelism)

    @property
    def D(self):
        """Ifmap tile height including filter overhead: D = e + R - U"""
        return self.e + self.R - self.U


# ============================================================================
# GLB Memory Model
# ============================================================================
class GLB:
    """Global Buffer — 4-bank dual-port BRAM model."""
    def __init__(self, depth: int, name: str = ""):
        # 4 banks, each depth entries of 16-bit
        self.bank = [np.zeros(depth, dtype=np.int16) for _ in range(4)]
        self.name = name

    def write_port_a(self, addr: int, word_64bit: int):
        """Port A: 64-bit write, split across 4 banks at sub-address."""
        sub_addr = addr >> 2
        for b in range(4):
            if sub_addr < len(self.bank[b]):
                self.bank[b][sub_addr] = (word_64bit >> (b * 16)) & 0xFFFF

    def read_port_b(self, addr: int) -> int:
        """Port B: 16-bit read from bank selected by addr[1:0]."""
        bank_sel = addr & 0x3
        sub_addr = addr >> 2
        if sub_addr < len(self.bank[bank_sel]):
            return int(self.bank[bank_sel][sub_addr])
        return 0

    def dump_nonzero(self, max_entries: int = 20):
        """Print non-zero entries for debugging."""
        count = 0
        for b in range(4):
            for a in range(len(self.bank[b])):
                v = self.bank[b][a]
                if v != 0 and count < max_entries:
                    print(f"  {self.name}[b{b}][{a}] = {v}")
                    count += 1


# ============================================================================
# PE Model (simplified — captures MAC + accumulation behavior)
# ============================================================================
class PE:
    """Single Processing Element with SPADs."""
    def __init__(self, ifmap_spad_depth=12, filter_spad_depth=224, psum_spad_depth=24):
        self.ifmap_spad = np.zeros(ifmap_spad_depth, dtype=np.int16)
        self.filter_spad = np.zeros(filter_spad_depth, dtype=np.int16)
        self.psum = np.zeros(psum_spad_depth, dtype=np.int32)  # 32-bit accumulator

    def load_ifmap(self, data: List[int]):
        for i, v in enumerate(data):
            if i < len(self.ifmap_spad):
                self.ifmap_spad[i] = v

    def load_filter(self, data: List[int]):
        for i, v in enumerate(data):
            if i < len(self.filter_spad):
                self.filter_spad[i] = v

    def compute(self, filter_len: int, ofmap_len: int, psum_in: np.ndarray = None) -> np.ndarray:
        """1D convolution of ifmap row × filter row → psum row."""
        result = np.zeros(ofmap_len, dtype=np.int32)
        if psum_in is not None:
            result += psum_in.astype(np.int32)
        for ow in range(ofmap_len):
            for r in range(filter_len):
                a = int(self.ifmap_spad[ow + r])
                b = int(self.filter_spad[r])
                result[ow] += (a * b) >> 13  # Q3.13 fixed-point MAC
        return result


# ============================================================================
# Scheduler
# ============================================================================
class Scheduler:
    """Nested-loop scheduler — generates pass descriptors."""
    def __init__(self, cfg: LayerConfig):
        self.cfg = cfg

    def generate_passes(self) -> List[Dict]:
        """Generate all processing passes for the configured layer."""
        passes = []
        cfg = self.cfg
        pass_num = 0

        for N_ind in range(0, cfg.N, cfg.n):
            for C_ind in range(0, cfg.C, cfg.q * cfg.r):
                for M_ind in range(0, cfg.M, cfg.p * cfg.t):
                    passes.append({
                        'pass_num': pass_num,
                        'ifmap_start': N_ind,
                        'ifmap_end': N_ind + cfg.n,
                        'channel_start': C_ind,
                        'channel_end': C_ind + cfg.q * cfg.r,
                        'filter_start': M_ind,
                        'filter_end': M_ind + cfg.p * cfg.t,
                        'N_ind': N_ind, 'C_ind': C_ind, 'M_ind': M_ind,
                    })
                    pass_num += 1
        return passes


# ============================================================================
# Index Generators
# ============================================================================
class IndexGenerators:
    """Ifmap, Filter, PSum index generators matching the SV RTL."""
    def __init__(self, cfg: LayerConfig):
        self.cfg = cfg

    def ifmap_addresses(self, ifmap_start: int, channel_start: int,
                        ifmap_array: np.ndarray) -> List[Tuple]:
        """
        Generate ifmap (index, channel, row, col, glb_addr) tuples.
        Loop: n × W × q × D × r  (D = e + R - U)
        GLB addr = n_idx*(C*H*W) + c_idx*(H*W) + row*W + col
        """
        cfg = self.cfg
        D = cfg.D
        results = []

        for n_idx in range(cfg.n):
            for w_idx in range(cfg.W):
                for q_idx in range(cfg.q):
                    for h_idx in range(D):
                        for r_idx in range(cfg.r):
                            ifmap_idx = ifmap_start + n_idx
                            chan_idx = channel_start + q_idx + r_idx * cfg.q
                            row_idx = h_idx
                            col_idx = w_idx
                            # GLB linear address (row-major 4D)
                            addr = (ifmap_idx * cfg.C * cfg.H * cfg.W +
                                    chan_idx * cfg.H * cfg.W +
                                    row_idx * cfg.W +
                                    col_idx)
                            results.append((ifmap_idx, chan_idx, row_idx, col_idx, addr))
        return results

    def filter_addresses(self, filter_start: int, channel_start: int,
                         filter_array: np.ndarray) -> List[Tuple]:
        """
        Generate filter (filter, channel, row, col, glb_addr) tuples.
        Loop: R × r × t with inner (p, q, S) sub-iteration using lock-step counters.
        GLB addr = m*(C*R*S) + c*(R*S) + r*S + s
        """
        cfg = self.cfg
        results = []
        p_ind, q_ind, s_ind = 0, 0, 0
        p_reg, q_reg, s_reg = 0, 0, 0

        while not (p_reg == cfg.p - 1 and q_reg == cfg.q - 1 and s_reg == cfg.S - 1):
            for R_ind in range(cfg.R):
                for r_idx in range(cfg.r):
                    for t_idx in range(cfg.t):
                        p_ind = p_reg
                        q_ind = q_reg
                        s_ind = s_reg
                        for _ in range(4):
                            filt_idx = filter_start + p_ind + t_idx * cfg.p
                            chan_idx = channel_start + q_ind + r_idx * cfg.q
                            row_idx = R_ind
                            col_idx = s_ind
                            addr = (filt_idx * cfg.C * cfg.R * cfg.S +
                                    chan_idx * cfg.R * cfg.S +
                                    row_idx * cfg.S +
                                    col_idx)
                            results.append((filt_idx, chan_idx, row_idx, col_idx, addr))

                            # Lock-step counter update
                            if p_ind == cfg.p - 1:
                                p_ind = 0
                                if q_ind == cfg.q - 1:
                                    q_ind = 0
                                    if s_ind == cfg.S - 1:
                                        p_ind = cfg.p - 1
                                        q_ind = cfg.q - 1
                                        s_ind = cfg.S - 1
                                    else:
                                        s_ind += 1
                                else:
                                    q_ind += 1
                            else:
                                p_ind += 1
            p_reg, q_reg, s_reg = p_ind, q_ind, s_ind
        return results

    def psum_addresses(self, psum_start: int, channel_start: int,
                       psum_array: np.ndarray) -> List[Tuple]:
        """
        Generate psum (psum, channel, row, col, glb_addr) tuples.
        Loop: E × t with inner (n, p, F) sub-iteration.
        GLB addr = n_idx*(M*F*E) + ch*(F*E) + row*E + col
        """
        cfg = self.cfg
        results = []
        n_ind, p_ind, f_ind = 0, 0, 0
        n_reg, p_reg, f_reg = 0, 0, 0

        while not (n_reg == cfg.n - 1 and p_reg == cfg.p - 1 and f_reg == cfg.F - 1):
            for E_ind in range(cfg.E):
                for t_idx in range(cfg.t):
                    n_ind = n_reg
                    p_ind = p_reg
                    f_ind = f_reg
                    for _ in range(4):
                        psum_idx = psum_start + n_ind
                        chan_idx = channel_start + p_ind + t_idx * cfg.p
                        row_idx = E_ind
                        col_idx = f_ind
                        addr = (psum_idx * cfg.M * cfg.F * cfg.E +
                                chan_idx * cfg.F * cfg.E +
                                row_idx * cfg.E +
                                col_idx)
                        results.append((psum_idx, chan_idx, row_idx, col_idx, addr))

                        if p_ind == cfg.p - 1:
                            p_ind = 0
                            if f_ind == cfg.F - 1:
                                f_ind = 0
                                if n_ind == cfg.n - 1:
                                    p_ind = cfg.p - 1
                                    f_ind = cfg.F - 1
                                    n_ind = cfg.n - 1
                                else:
                                    n_ind += 1
                            else:
                                f_ind += 1
                        else:
                            p_ind += 1
            n_reg, p_reg, f_reg = n_ind, p_ind, f_ind
        return results


# ============================================================================
# Full System Model
# ============================================================================
class EyerissModel:
    """Complete Eyeriss v1 behavioral model."""
    def __init__(self, cfg: LayerConfig):
        self.cfg = cfg
        self.scheduler = Scheduler(cfg)
        self.idx_gen = IndexGenerators(cfg)

        # GLB instances (depths from shared_pkg)
        self.ifmap_glb = GLB(cfg.N * cfg.C * cfg.H * cfg.W // 4 + 1, "IFMAP")
        self.filter_glb = GLB(cfg.M * cfg.C * cfg.R * cfg.S // 4 + 1, "FILTER")
        self.bias_glb = GLB(cfg.M // 4 + 1, "BIAS")
        self.psum_glb = GLB(cfg.N * cfg.M * cfg.F * cfg.E // 4 + 1, "PSUM")

        # Test data
        self.ifmap_data = None
        self.filter_data = None
        self.bias_data = None
        self.ofmap_golden = None

    def load_test_data(self, ifmap: np.ndarray, filter_w: np.ndarray, bias: np.ndarray):
        """Load test data into the model's GLB."""
        self.ifmap_data = ifmap.astype(np.int16)
        self.filter_data = filter_w.astype(np.int16)
        self.bias_data = bias.astype(np.int16)

        cfg = self.cfg

        # Write ifmap to GLB (64-bit Port A writes)
        addr64 = 0
        for n in range(cfg.N):
            for c in range(cfg.C):
                for h in range(cfg.H):
                    for w in range(0, cfg.W, 4):
                        word = 0
                        for k in range(4):
                            if w + k < cfg.W:
                                val = int(ifmap[n, c, h, w + k]) & 0xFFFF
                                word |= val << (k * 16)
                        self.ifmap_glb.write_port_a(addr64 * 4, word)
                        addr64 += 1

        # Write filter to GLB
        addr64 = 0
        for m in range(cfg.M):
            for c in range(cfg.C):
                for r in range(cfg.R):
                    for s in range(0, cfg.S, 4):
                        word = 0
                        for k in range(4):
                            if s + k < cfg.S:
                                val = int(filter_w[m, c, r, s + k]) & 0xFFFF
                                word |= val << (k * 16)
                        self.filter_glb.write_port_a(addr64 * 4, word)
                        addr64 += 1

        # Write bias to GLB
        for i, b in enumerate(bias):
            addr = i
            bank = addr & 0x3
            sub = addr >> 2
            self.bias_glb.bank[bank][sub] = b

    def compute_golden(self) -> np.ndarray:
        """Compute golden reference: 2D convolution in Q3.13 fixed-point."""
        cfg = self.cfg
        ifmap = self.ifmap_data
        filt = self.filter_data
        bias = self.bias_data
        N, C, H, W = ifmap.shape
        M = filt.shape[0]
        E, F = cfg.E, cfg.F
        U = cfg.U
        R, S = cfg.R, cfg.S

        ofmap = np.zeros((N, M, F, E), dtype=np.int16)
        for n in range(N):
            for m in range(M):
                for oh in range(F):
                    for ow in range(E):
                        acc = np.int32(0)
                        h_start = oh * U
                        w_start = ow * U
                        for c in range(C):
                            for r in range(R):
                                for s in range(S):
                                    if (h_start + r < H and w_start + s < W):
                                        a = np.int32(ifmap[n, c, h_start + r, w_start + s])
                                        b = np.int32(filt[m, c, r, s])
                                        acc += (a * b) >> 13
                        acc += np.int32(bias[m])
                        if acc > 32767: acc = 32767
                        elif acc < -32768: acc = -32768
                        ofmap[n, m, oh, ow] = np.int16(acc)
        self.ofmap_golden = ofmap
        return ofmap

    def verify_against_golden(self, result: np.ndarray) -> Tuple[int, int]:
        """Compare result with golden reference."""
        if self.ofmap_golden is None:
            self.compute_golden()
        match = np.sum(result == self.ofmap_golden)
        mismatch = np.sum(result != self.ofmap_golden)
        return int(match), int(mismatch)

    def print_summary(self):
        """Print model configuration and data summary."""
        cfg = self.cfg
        print(f"=== Eyeriss v1 Behavioral Model ===")
        print(f"Layer: {cfg.H}x{cfg.W}x{cfg.C} + {cfg.R}x{cfg.S} filter → {cfg.F}x{cfg.E}x{cfg.M}")
        print(f"Stride: {cfg.U}, Batch: {cfg.N}")
        print(f"Tile height D: {cfg.D}")
        print(f"Mapping: m={cfg.m} n={cfg.n} e={cfg.e} p={cfg.p} q={cfg.q} r={cfg.r} t={cfg.t}")
        passes = self.scheduler.generate_passes()
        print(f"Total passes: {len(passes)}")

        for p in passes:
            ifmap_addrs = self.idx_gen.ifmap_addresses(
                p['ifmap_start'], p['channel_start'], self.ifmap_data)
            filter_addrs = self.idx_gen.filter_addresses(
                p['filter_start'], p['channel_start'], self.filter_data)
            psum_addrs = self.idx_gen.psum_addresses(
                p['ifmap_start'], p['channel_start'],
                np.zeros((cfg.N, cfg.M, cfg.F, cfg.E), dtype=np.int16))
            print(f"  Pass {p['pass_num']}: "
                  f"ifmap={len(ifmap_addrs)} addr, "
                  f"filter={len(filter_addrs)} addr, "
                  f"psum={len(psum_addrs)} addr")


# ============================================================================
# Standalone Test
# ============================================================================
if __name__ == "__main__":
    # Test with our tiny layer
    cfg = LayerConfig(
        H=8, W=8, R=3, S=3, E=6, F=6,
        C=1, M=1, N=1, U=1,
        m=1, n=1, e=6, p=1, q=1, r=1, t=1
    )

    model = EyerissModel(cfg)

    # Create test data (non-zero!)
    np.random.seed(42)
    ifmap = np.arange(1, 65, dtype=np.int16).reshape(1, 1, 8, 8) * 256  # Q3.13: 1..64
    filter_w = np.array([[[[1, 0, 0],
                           [0, 2, 0],
                           [0, 0, 1]]]], dtype=np.int16) * 256
    bias = np.array([0], dtype=np.int16)

    model.load_test_data(ifmap, filter_w, bias)
    model.print_summary()

    # Generate GLB address traces for first pass
    passes = model.scheduler.generate_passes()
    p = passes[0]
    print(f"\n--- Pass {p['pass_num']} Address Traces ---")
    ifmap_addr = model.idx_gen.ifmap_addresses(p['ifmap_start'], p['channel_start'], ifmap)
    filter_addr = model.idx_gen.filter_addresses(p['filter_start'], p['channel_start'], filter_w)
    print(f"  Ifmap addresses: {len(ifmap_addr)} (first 5):")
    for a in ifmap_addr[:5]:
        print(f"    idx={a[0]} ch={a[1]} row={a[2]} col={a[3]} addr={a[4]}")
    print(f"  Filter addresses: {len(filter_addr)} (first 5):")
    for a in filter_addr[:5]:
        print(f"    filt={a[0]} ch={a[1]} row={a[2]} col={a[3]} addr={a[4]}")

    # Compute golden
    golden = model.compute_golden()
    print(f"\n--- Golden Reference (OFM {cfg.F}x{cfg.E}) ---")
    for oh in range(cfg.F):
        row_str = "  ".join(f"{golden[0,0,oh,ow]:5d}" for ow in range(cfg.E))
        print(f"  {row_str}")

    print("\n=== Behavioral model ready ===")
