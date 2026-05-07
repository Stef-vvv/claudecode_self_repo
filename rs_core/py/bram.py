"""
BRAM — Block RAM behavioral model.

Memory organization:
  - 128-bit access: 16 bytes per row (for ifmap/ofmap, Q_IN=5 → 16 elements)
  - 32-bit access: 4 bytes per row (for filter, Q_W=8 → 3 values + 1 padding)
"""

class BRAM:
    def __init__(self, size):
        self.size = size
        self.mem = [0] * size

    def read(self, addr, access_width):
        """Read from logical address, scaled by access width."""
        if access_width == 128:
            phys = addr * 16
            return self.mem[phys:phys + 16].copy()
        elif access_width == 32:
            phys = addr * 4
            return self.mem[phys:phys + 4].copy()
        else:
            raise ValueError("Access width must be 128 or 32")

    def write(self, addr, data, access_width):
        """Write to logical address."""
        if access_width == 128:
            phys = addr * 16
            for i, v in enumerate(data):
                self.mem[phys + i] = v
        elif access_width == 32:
            phys = addr * 4
            for i, v in enumerate(data):
                self.mem[phys + i] = v

    def read_byte(self, addr):
        """Direct byte-level read."""
        return self.mem[addr]

    def write_byte(self, addr, value):
        """Direct byte-level write."""
        self.mem[addr] = value
