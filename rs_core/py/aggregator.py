"""
Aggregator — Accumulates partial sums from PE arrays across input channels.

Receives PE array outputs, reads previous partial results from BRAM,
accumulates, and prepares data for write-back.
"""

class Aggregator:
    def __init__(self, output_bram, pe_arrays):
        self.output_bram = output_bram
        self.pe_arrays = pe_arrays
        self.address_queue = []

        # State
        self.finished = 0
        self.output = [0] * 16
        self.output_address = 0

    def process(self):
        self.finished = 0
        for arr in self.pe_arrays:
            if arr.finished:
                # Read previous partial result from BRAM
                if self.address_queue:
                    addr = self.address_queue.pop(0)
                    prev = self.output_bram.read(addr, 128)
                    self.output = prev.copy()
                else:
                    self.output = [0] * 16

                # Accumulate PE array results into output buffer
                for i, arr_output in enumerate(self.pe_arrays):
                    if arr_output.finished:
                        result = arr_output.output
                        for j in range(min(len(result), len(self.output) - i * 3)):
                            self.output[i * 3 + j] += result[j]

                self.finished = 1
                self.output_address = addr if self.address_queue else 0
                break  # One array per cycle
