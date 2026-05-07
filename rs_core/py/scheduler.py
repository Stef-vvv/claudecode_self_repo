"""
Scheduler — Address generation and data distribution for RS dataflow.

Controls:
  - data_port: broadcast input data to PE array (5 elements)
  - filter_port: filter weights to column-0 PEs (3 elements)
  - start: trigger PE(0,0) at the beginning of each tile
  - new_in_data: data-valid strobe for PEs along start propagation path

Timing for one 3×3 conv tile (K=3, stride=1, 1 input channel, 1 output channel):
  Cycle 0: data=row0[0:5], filter=f_row0, start_global=1 → PE(0,0) latches
  Cycle 1: data=row1[0:5], filter=f_row1 → PE(1,0) & PE(0,1) latch
  Cycle 2: data=row2[0:5], filter=f_row2 → PE(2,0), PE(1,1), PE(0,2) latch
  Cycle 3..5: pipeline drain (no new data)
  Cycle ~6: result ready at PE(2,0)
"""

import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from pe_array import PEArray
from bram import BRAM


class Scheduler:
    def __init__(self, input_bram, filter_bram, n_arrays=1):
        self.input_bram = input_bram
        self.filter_bram = filter_bram

        # Data ports (one per PE array)
        self.data_ports = [[0] * 5 for _ in range(n_arrays)]
        self.filter_port = [0] * 3

        # PE arrays
        self.pe_arrays = []
        for i in range(n_arrays):
            self.pe_arrays.append(PEArray(3, self.data_ports[i], self.filter_port))

        self.aggregator = None
        self.write_ram = None

        # State
        self.cycle = 0
        self.total_cycles = 0

    def process_step(self):
        """Execute one clock cycle for all PE arrays."""
        for arr in self.pe_arrays:
            arr.process()
        if self.aggregator:
            self.aggregator.process()
        if self.write_ram:
            self.write_ram.process()
        self.cycle += 1
        self.total_cycles += 1

    def run_one_tile(self, ifmap_rows, filter_rows):
        """
        Run one 3×3 convolution tile.

        ifmap_rows: list of 3 rows, each row is a list of 5 values
        filter_rows: list of 3 filter rows, each is a list of 3 weights

        Returns: (output_row, cycles_taken) where output_row is a list of 3 values
        """
        arr = self.pe_arrays[0]

        # Reset all PE state
        for r in range(3):
            for c in range(3):
                arr.grid[r][c].new_in_data = 0
                arr.grid[r][c].start = 0

        cycles = 0
        result = None
        while True:
            # Feed data on cycles 0, 1, 2
            if cycles < 3:
                self.data_ports[0][:] = ifmap_rows[cycles]
                self.filter_port[:] = filter_rows[cycles]
                for r in range(3):
                    for c in range(3):
                        arr.grid[r][c].new_in_data = 1
                if cycles == 0:
                    arr.grid[0][0].start = 1
            else:
                for r in range(3):
                    for c in range(3):
                        arr.grid[r][c].new_in_data = 0

            self.process_step()
            cycles += 1

            # Capture result when first bottom PE finishes
            if arr.finished and result is None:
                result = list(arr.output)

            # Continue until all PEs return to IDLE (pipeline drain)
            if cycles >= 5 and result is not None:
                all_idle = True
                for r in range(3):
                    for c in range(3):
                        if arr.grid[r][c].state != 0:
                            all_idle = False
                if all_idle:
                    break

            if cycles > 30:
                print("WARNING: Scheduler run_one_tile exceeded 30 cycles")
                break

        return result if result is not None else [0, 0, 0]

    def compute_2d_conv(self, ifmap, filters, stride=1):
        """
        Full 2D convolution of ifmap[H][W] with filters[K][K].

        ifmap: 2D list H×W (with padding already applied)
        filters: 2D list K×K
        stride: convolution stride

        Returns: 2D output feature map
        """
        H = len(ifmap)
        W = len(ifmap[0])
        K = len(filters)
        out_H = (H - K) // stride + 1
        out_W = (W - K) // stride + 1

        ofmap = [[0] * out_W for _ in range(out_H)]

        for oh in range(out_H):
            for ow in range(out_W):
                # Extract 3×3 input tile (K=3, we need 5-wide rows for sliding window of 3)
                ifmap_rows = []
                for kh in range(K):
                    row_start = oh * stride + kh
                    # Extract 5-element row for sliding window (3 outputs per row)
                    col_start = ow * stride
                    row_data = []
                    for kw in range(K + 2):  # 5 elements for 3×3 conv with stride 1
                        c = col_start + kw
                        if 0 <= row_start < H and 0 <= c < W:
                            row_data.append(ifmap[row_start][c])
                        else:
                            row_data.append(0)  # zero padding
                    ifmap_rows.append(row_data)

                filter_rows = [list(f) for f in filters]

                result = self.run_one_tile(ifmap_rows, filter_rows)
                # result has 3 values (one per sliding window position)
                # For 1 output pixel, we use position 0
                # For 3 output pixels (stride=1 within a 5-wide input), all 3 are valid
                # But for ow position, we're computing one specific pixel at a time
                # The PE array produces 3 outputs (one per column of sliding window)
                for pw in range(min(3, out_W - ow)):
                    ofmap[oh][ow + pw] += result[pw]

        return ofmap
