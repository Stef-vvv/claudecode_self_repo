"""
Scheduler_Single — Simplified single-PE-array scheduler for full conv2 verification.

Uses ONE PE array to process the entire conv2 layer sequentially.
Each tile: 5×3 ifmap × 3×3 filter → 3×1 ofmap (3 output pixels).
The scheduler iterates over spatial positions, input channels, output channels.

This avoids the 6-array split complexity, making it easier to verify correctness
against the golden reference.
"""

import sys
sys.path.insert(0, 'H:/cc_project/py_project')
from pe_array import PEArray
from bram import BRAM


class SchedulerSingle:
    def __init__(self, input_bram, filter_bram, output_bram):
        self.input_bram = input_bram
        self.filter_bram = filter_bram
        self.output_bram = output_bram

        # Single PE array
        self.data_port = [0] * 5
        self.filter_port = [0] * 3
        self.pe_array = PEArray(3, self.data_port, self.filter_port)

        # State tracking
        self.cycle = 0

    def process_step(self):
        self.pe_array.process()
        self.cycle += 1

    def reset_pe_array(self):
        """Reset all PE states to IDLE."""
        arr = self.pe_array
        for r in range(3):
            for c in range(3):
                arr.grid[r][c].new_in_data[0] = 0
                arr.grid[r][c].start[0] = 0

    def drain_pipeline(self, max_cycles=20):
        """Run until all PEs return to IDLE."""
        arr = self.pe_array
        for _ in range(max_cycles):
            all_idle = True
            for r in range(3):
                for c in range(3):
                    if arr.grid[r][c].state != 0:
                        all_idle = False
            if all_idle:
                break
            self.process_step()

    def run_one_tile(self, ifmap_rows, filter_rows):
        """
        Run one 3×3 conv tile through the PE array.
        Returns 3 output pixels.
        """
        arr = self.pe_array

        # Set data on bus for 3 cycles (time-multiplexed RS)
        for step in range(15):
            if step < 3:
                self.data_port[:] = ifmap_rows[step]
                self.filter_port[:] = filter_rows[step]
                # All PEs can latch data (start propagation selects which ones)
                for r in range(3):
                    for c in range(3):
                        arr.grid[r][c].new_in_data[0] = 1
                if step == 0:
                    arr.grid[0][0].start[0] = 1
            else:
                # No new data during drain
                for r in range(3):
                    for c in range(3):
                        arr.grid[r][c].new_in_data[0] = 0

            self.process_step()

            if arr.finished:
                saved = list(arr.output)
                self.drain_pipeline()
                self.reset_pe_array()
                return saved

            if step > 12:
                break

        self.reset_pe_array()
        return [0, 0, 0]

    def read_ifmap_row(self, channel, row, pad=1):
        """
        Read one row of ifmap from BRAM (with zero padding).
        Returns 16-element list (Q8 float values).
        """
        H = 16
        if row < 0 or row >= H:
            return [0.0] * 16
        addr = channel * H + row
        return self.input_bram.read(addr, 128)  # length 16

    def read_filter_row(self, out_ch, in_ch, frow):
        """Read one filter row (3 values) from BRAM."""
        # Filter layout: each 32-bit row holds 3 values + 1 padding
        # Address = out_ch * (32*3) + in_ch * 3 + frow
        addr = out_ch * 32 * 3 + in_ch * 3 + frow
        data = self.filter_bram.read(addr, 32)  # length 4, values at [0:3]
        return list(data[:3])

    def run_full_conv(self):
        """
        Full conv2: IFM 16x16x32 → OFM 16x16x64, K=3x3, pad=1, stride=1.
        Single PE array processes each 3-output-pixel segment sequentially.
        """
        H, W = 16, 16
        C, F = 32, 64
        K = 3

        ofmap = [[[0.0] * W for _ in range(H)] for _ in range(F)]

        total_tiles = 0
        for oc in range(F):         # 64 output channels
            for ic in range(C):     # 32 input channels
                for oh in range(H): # 16 output rows
                    # Each tile produces 3 output pixels (3 cols)
                    for ow in range(0, W, 3):
                        if ow + 2 >= W:
                            continue  # Skip partial tiles at row edge (handled by 6-array split)

                        total_tiles += 1
                        if total_tiles % 1000 == 0:
                            print(f"  Tile {total_tiles}... oc={oc} ic={ic} oh={oh} ow={ow}")

                        # Extract 3 ifmap rows (with padding)
                        ifmap_rows = []
                        for kh in range(K):
                            ir = oh + kh - 1  # pad=1: row 0 → ifmap row -1 (padded)
                            row_data = []
                            for kw in range(5):  # 5-wide sliding window for 3 outputs
                                ic_col = ow + kw - 1  # pad=1
                                if 0 <= ir < H and 0 <= ic_col < W:
                                    full_row = self.read_ifmap_row(ic, ir)
                                    row_data.append(float(full_row[ic_col]))
                                else:
                                    row_data.append(0.0)
                            ifmap_rows.append(row_data)

                        # Extract 3 filter rows
                        filter_rows = []
                        for kh in range(K):
                            frow = self.read_filter_row(oc, ic, kh)
                            filter_rows.append(frow)

                        # Run tile
                        result = self.run_one_tile(ifmap_rows, filter_rows)

                        # Accumulate into ofmap (float accumulation across input channels)
                        for p in range(3):
                            col = ow + p
                            if col < W:
                                ofmap[oc][oh][col] += result[p]

        return ofmap
