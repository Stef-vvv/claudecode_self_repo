"""BRAM - 块存储器行为模型 (匹配原工程)"""
class BRAM:
    def __init__(self, size):
        self.size = size
        self.mem = [0] * size

    def get_physical_address(self, addr, access_width):
        if access_width == 128:
            return addr * 16
        elif access_width == 32:
            return addr * 4
        else:
            raise ValueError("Unsupported access width")

    def read(self, addr, access_width):
        phys = self.get_physical_address(addr, access_width)
        if access_width == 128:
            return self.mem[phys:phys + 16].copy()
        elif access_width == 32:
            return self.mem[phys:phys + 4].copy()

    def write(self, addr, data, access_width):
        phys = self.get_physical_address(addr, access_width)
        if access_width == 128:
            for i in range(min(len(data), 16)):
                self.mem[phys + i] = data[i]
        elif access_width == 32:
            for i in range(min(len(data), 4)):
                self.mem[phys + i] = data[i]
