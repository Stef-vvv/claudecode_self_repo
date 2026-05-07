"""
PE Array — 3×3 Row-Stationary Systolic Array

Architecture:
  - Data: broadcast to ALL PEs (same data_port)
  - Filter: propagates RIGHT from column 0 (externally supplied)
  - Partial sums: propagate DOWN from row 0
  - Start signal: propagates DIAGONALLY (above_out_start OR left_out_start)
  - Output: result from first-finished PE in bottom row

This is a SIMPLIFIED Row Stationary array. In true RS, data is shared
diagonally between PEs. Here it's broadcast, with the scheduler
responsible for putting the right data on the bus at the right time.
Only PEs along the start-propagation path perform useful computation.
"""

import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from pe import PE


class PEArray:
    def __init__(self, n=3, data_port=None, filter_port=None):
        self.n = n

        # External ports (shared buses)
        self.data_port = data_port if data_port is not None else [0] * 5
        self.filter_port = filter_port if filter_port is not None else [0] * 3

        # Create n×n grid of PEs
        self.grid = [[PE() for _ in range(n)] for _ in range(n)]

        # Connect external ports
        for r in range(n):
            for c in range(n):
                self.grid[r][c].in_data = self.data_port
                if c == 0:
                    self.grid[r][c].in_filter = self.filter_port

        # Array-level outputs
        self.finished = 0
        self.output = [0] * 3

    def process(self):
        """One clock cycle for the entire array."""
        # ---- Phase 1: All PEs compute in parallel ----
        for r in range(self.n):
            for c in range(self.n):
                self.grid[r][c].process_one()

        # ---- Phase 2: Inter-PE communication ----
        for r in range(self.n):
            for c in range(self.n):
                # Filter: propagate RIGHT
                if c != 0:
                    self.grid[r][c].in_filter = list(self.grid[r][c-1].out_filter)

                # Partial sum: propagate DOWN (unconditional in hardware,
                # gated by finished in software for correctness)
                if r != 0:
                    if self.grid[r-1][c].finished:
                        self.grid[r][c].in_result = list(self.grid[r-1][c].result)

                # Start: propagate DIAGONALLY
                above_start = 1 if (r > 0 and self.grid[r-1][c].out_start) else 0
                left_start = 1 if (c > 0 and self.grid[r][c-1].out_start) else 0
                if c != 0 or r != 0:  # Not top-left (controlled by scheduler)
                    self.grid[r][c].start = above_start or left_start

        # ---- Phase 3: Detect completion ----
        self.finished = 0
        for c in range(self.n):
            if self.grid[self.n - 1][c].finished:
                self.output = list(self.grid[self.n - 1][c].result)
                self.finished = 1
                break

    # ---- Debug helpers ----
    def print_grid(self, attr, label=None):
        if label:
            print(f"\n--- {label} ---")
        for r in range(self.n):
            row = []
            for c in range(self.n):
                val = getattr(self.grid[r][c], attr)
                row.append(str(val))
            print(" | ".join(row))

    def print_state(self, step):
        print(f"\n{'='*50}")
        print(f"  Step {step}")
        print(f"{'='*50}")
        self.print_grid("state", "State")
        self.print_grid("out_start", "out_start")
        self.print_grid("data", "data (reg)")
        self.print_grid("filt", "filter (reg)")
        self.print_grid("result", "result")
        self.print_grid("finished", "finished")
        print(f"Array finished: {self.finished}")
        print(f"Array output: {self.output}")
