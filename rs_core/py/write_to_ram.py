"""WriteRam — Write aggregated output back to BRAM."""

class WriteRam:
    def __init__(self, output_bram, aggregator):
        self.output_bram = output_bram
        self.aggregator = aggregator
        self.finished = 0

    def process(self):
        self.finished = 0
        if self.aggregator.finished:
            self.output_bram.write(
                self.aggregator.output_address,
                self.aggregator.output,
                128
            )
            self.finished = 1
