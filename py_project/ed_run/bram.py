"""BRAM - 块存储器模型 (匹配原工程)"""
class BRAM:
    def __init__(self, size):
        self.size = size
        self.mem = [0.0] * size

    def read(self, addr, access_width):
        if access_width == 128:
            phys = addr * 16
            return self.mem[phys:phys + 16].copy()
        elif access_width == 32:
            phys = addr * 4
            return self.mem[phys:phys + 4].copy()
        else:
            raise ValueError("Unsupported access width")

    def write(self, addr, data, access_width):
        if access_width == 128:
            phys = addr * 16
            for i in range(min(len(data), 16)):
                self.mem[phys + i] = data[i]
        elif access_width == 32:
            phys = addr * 4
            for i in range(min(len(data), 4)):
                self.mem[phys + i] = data[i]
