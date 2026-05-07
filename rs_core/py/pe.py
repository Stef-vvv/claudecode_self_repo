"""
PE - Row-Stationary Processing Element (Hardware Model)

One process_one() call = one clock cycle. Register updates at end of cycle.
Inputs sampled at cycle start, outputs valid after register update.

State machine (5 cycles total):
  IDLE(0) --start--> MAC[iter0], latch data/filt, compute dot(offset=0)
  MAC[iter1]       : compute dot(offset=1), clear out_start
  MAC[iter2]       : compute dot(offset=2), -> ACC
  ACC              : accumulate in_result, finished=1, -> DONE
  DONE             : finished=0, -> IDLE
"""

class PE:
    def __init__(self, in_width=5, w_width=8, acc_width=16):
        self.IN_WIDTH = in_width
        self.W_WIDTH = w_width
        self.ACC_WIDTH = acc_width

        # Input ports
        self.start = 0
        self.new_in_data = 0
        self.in_data = [0] * 5
        self.in_filter = [0] * 3
        self.in_result = [0] * 3

        # Output ports
        self.out_result = [0] * 3
        self.out_filter = [0] * 3
        self.out_start = 0
        self.finished = 0

        # Internal state registers
        self.state = 0     # 0=IDLE, 1=MAC, 2=ACC, 3=DONE
        self.iter = 0      # 0,1,2 MAC iteration count
        self.data = [0] * 5
        self.filt = [0] * 3
        self.result = [0] * 3

    def _dot(self, d, f, offset):
        """Combinational: dot(d[offset:offset+3], f[0:3])."""
        return d[offset]*f[0] + d[offset+1]*f[1] + d[offset+2]*f[2]

    def process_one(self):
        # ---- Sample inputs at cycle start ----
        start_in = self.start
        new_data_in = self.new_in_data
        in_data_vec = list(self.in_data)
        in_filt_vec = list(self.in_filter)
        in_res_vec = list(self.in_result)

        # ---- Next-state defaults (keep current) ----
        nxt_state = self.state
        nxt_iter = self.iter
        nxt_data = list(self.data)
        nxt_filt = list(self.filt)
        nxt_result = list(self.result)
        nxt_finished = 0
        nxt_out_start = 0
        nxt_out_filter = list(self.filt)

        if self.state == 0:  # IDLE
            if start_in:
                nxt_state = 1
                nxt_iter = 0
                nxt_out_start = 1
                if new_data_in:
                    nxt_data = in_data_vec
                    nxt_filt = in_filt_vec
                # Hardware: when start=1, dot(offset=0) uses INPUT port data
                # (latched at end of cycle into registers)
                data_for_dot = nxt_data  # newly-latched (or old if no new_data_in)
                filt_for_dot = nxt_filt
                nxt_result[0] = self._dot(data_for_dot, filt_for_dot, 0)
                nxt_iter = 1

        elif self.state == 1:  # MAC
            if self.iter == 0:
                # Edge case: shouldn't happen with normal start flow
                nxt_result[0] = self._dot(self.data, self.filt, 0)
                nxt_iter = 1
                nxt_out_start = 1
            elif self.iter == 1:
                nxt_result[1] = self._dot(self.data, self.filt, 1)
                nxt_iter = 2
            elif self.iter == 2:
                nxt_result[2] = self._dot(self.data, self.filt, 2)
                nxt_iter = 0
                nxt_state = 2  # -> ACC

        elif self.state == 2:  # ACC
            nxt_result[0] = self.result[0] + in_res_vec[0]
            nxt_result[1] = self.result[1] + in_res_vec[1]
            nxt_result[2] = self.result[2] + in_res_vec[2]
            nxt_finished = 1
            nxt_state = 3

        elif self.state == 3:  # DONE
            nxt_finished = 0
            nxt_state = 0
            nxt_iter = 0

        # ---- Register update (posedge) ----
        self.state = nxt_state
        self.iter = nxt_iter
        self.data = nxt_data
        self.filt = nxt_filt
        self.result = nxt_result
        self.finished = nxt_finished
        self.out_start = nxt_out_start
        self.out_filter = nxt_out_filter
        self.out_result = list(nxt_result)

        # Start is auto-cleared when consumed (IDLE + start → MAC)
        if self.state == 0 and start_in:
            self.start = 0
        # new_in_data is auto-cleared only when data is actually latched
        if self.state == 0 and start_in and new_data_in:
            self.new_in_data = 0
