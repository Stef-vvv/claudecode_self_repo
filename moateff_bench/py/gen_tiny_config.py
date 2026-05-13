"""
Generate scan chain config files for a tiny test layer that fits entirely in GLB.

Test layer: H=8, W=8, C=1, R=3, S=3, M=1, N=1, U=1 (stride 1, no padding)
OFM: E=6, F=6

PE array usage: 3 rows (for 3 filter rows) × 1 column (for 1 filter) = 3 PEs
PE positions: [0][0], [1][0], [2][0]

Row-Stationary dataflow within a 3×1 column:
  - PE[2][0] (bottom): receives ifmap row 0, filter row 2, first to start
  - PE[1][0] (middle):  receives ifmap row 1, filter row 1
  - PE[0][0] (top):     receives ifmap row 2, filter row 0, produces final output
  - PSum flows upward: PE[2].opsum → PE[1].ipsum → PE[0].opsum → GON → GLB

Mapping params: m=1, n=1, e=6, p=1, q=1, r=1, t=1

Config file formats:
  parameters.txt:    key = value pairs
  enables.txt:       12 rows × 14 cols (1 or 0)
  ipsum_ln_selectors.txt: 12 × 14 (1=from GIN, 0=from PE below)
  opsum_ln_selectors.txt: 12 × 14 (1=to GON, 0=to PE above)
  ifmap_ids.txt:     12 rows × 15 (1 row_tag + 14 col_tags)
  filters_ids.txt:   12 rows × 15 (15 column IDs, 4-bit each)
  ipsum_ids.txt:     12 rows × 15
  opsum_ids.txt:     12 rows × 15
"""

import os

# ============================================================
# Layer parameters
# ============================================================
H, W = 8, 8       # ifmap spatial
R, S = 3, 3       # filter spatial
C = 1             # input channels
M = 1             # output filters
N = 1             # batch
U = 1             # stride
E = (H - R) // U + 1  # OFM height = 6
F = (W - S) // U + 1  # OFM width  = 6

# Mapping parameters
m_val = 1   # filters per pass group
n_val = 1   # ifmaps per pass group
e_val = E   # OFM tile height
p_val = 1   # filters per PE set (horizontal)
q_val = 1   # channels per PE set
r_val = 1   # column groups for channels
t_val = 1   # row groups for filters

# PE array constants
NUM_ROWS = 12
NUM_COLS = 14

# ============================================================
# Generate: parameters.txt
# ============================================================
params = f"""H = {H}
W = {W}
R = {R}
S = {S}
E = {E}
F = {F}
C = {C}
M = {M}
N = {N}
U = {U}
m = {m_val}
n = {n_val}
e = {e_val}
p = {p_val}
q = {q_val}
r = {r_val}
t = {t_val}
"""

# ============================================================
# Generate: enables.txt (12×14)
# Only PEs [0][0], [1][0], [2][0] enabled
# ============================================================
enables = []
for i in range(NUM_ROWS):
    row = []
    for j in range(NUM_COLS):
        if i in [0, 1, 2] and j == 0:
            row.append('1')
        else:
            row.append('0')
    enables.append('   '.join(row))

# ============================================================
# Generate: ipsum_ln_selectors.txt (12×14)
# Within 3-row column group:
#   Row 2 (bottom): gets ipsum from GIN  → ln_sel = 1
#   Row 1: gets ipsum from PE[2]          → ln_sel = 0
#   Row 0: gets ipsum from PE[1]          → ln_sel = 0
# All other rows: disabled (0)
# ============================================================
ipsum_ln = []
for i in range(NUM_ROWS):
    row = []
    for j in range(NUM_COLS):
        if i == 2 and j == 0:
            row.append('1')  # bottom PE: from GIN
        else:
            row.append('0')
    ipsum_ln.append('   '.join(row))

# ============================================================
# Generate: opsum_ln_selectors.txt (12×14)
# Within 3-row column group:
#   Row 0 (top): sends opsum to GON    → ln_sel = 1
#   Row 1: sends opsum to PE[0]         → ln_sel = 0
#   Row 2: sends opsum to PE[1]         → ln_sel = 0
# All other rows: disabled (0)
# ============================================================
opsum_ln = []
for i in range(NUM_ROWS):
    row = []
    for j in range(NUM_COLS):
        if i == 0 and j == 0:
            row.append('1')  # top PE: to GON
        else:
            row.append('0')
    opsum_ln.append('   '.join(row))

# ============================================================
# Generate: ifmap_ids.txt (12 rows × 15 values)
# Each row: [row_tag(4-bit)] + [14 col_tags(5-bit)]
#   Row 0: row_tag=0, col[0]=0 (others=31 disabled)
#   Row 1: row_tag=1, col[0]=0
#   Row 2: row_tag=2, col[0]=0
#   Other rows: disabled (row_tag=15, col_tags=31)
# row_tag=15 means disabled; col_tag=31 means disabled
# ============================================================
DISABLED_4BIT = 15
DISABLED_5BIT = 31

ifmap_ids = []
for i in range(NUM_ROWS):
    if i in [0, 1, 2]:
        row_tag = i
        cols = [0] + [DISABLED_5BIT] * (NUM_COLS - 1)  # only col 0 active
    else:
        row_tag = DISABLED_4BIT
        cols = [DISABLED_5BIT] * NUM_COLS
    row_str = f"{row_tag:2d}  " + "  ".join(f"{c:2d}" for c in cols)
    ifmap_ids.append(row_str)

# ============================================================
# Generate: filters_ids.txt (12 rows × 15 values)
# Each row: 15 × 4-bit column IDs
# For our 3-row × 1-col config:
#   Row 0: receives filter row 0 → tag=0
#   Row 1: receives filter row 1 → tag=1
#   Row 2: receives filter row 2 → tag=2
# For the single column j=0, all 3 rows share the same column ID=0
# ============================================================
filter_ids = []
for i in range(NUM_ROWS):
    if i in [0, 1, 2]:
        tags = [i] + [DISABLED_4BIT] * (NUM_COLS - 1)
    else:
        tags = [DISABLED_4BIT] * NUM_COLS
    # Add an extra tag at the beginning (matching conv1 format: 15 values per row)
    # First value is the row tag, rest are column tags
    row_str = f"{DISABLED_4BIT:2d}  " + "  ".join(f"{t:2d}" for t in tags)
    filter_ids.append(row_str)

# ============================================================
# Generate: ipsum_ids.txt (12 rows × 15 values)
# The bottom PE (row 2) receives ipsum from GIN
# ============================================================
ipsum_ids = []
for i in range(NUM_ROWS):
    if i == 2:
        # Row 2 receives ipsum from GIN via tag 0
        tags = [0] + [DISABLED_4BIT] * (NUM_COLS - 1)
    else:
        tags = [DISABLED_4BIT] * NUM_COLS
    row_str = f"{DISABLED_4BIT:2d}  " + "  ".join(f"{t:2d}" for t in tags)
    ipsum_ids.append(row_str)

# ============================================================
# Generate: opsum_ids.txt (12 rows × 15 values)
# The top PE (row 0) sends opsum to GON
# ============================================================
opsum_ids = []
for i in range(NUM_ROWS):
    if i == 0:
        # Row 0 sends opsum to GON via tag 0
        tags = [0] + [DISABLED_4BIT] * (NUM_COLS - 1)
    else:
        tags = [DISABLED_4BIT] * NUM_COLS
    row_str = f"{DISABLED_4BIT:2d}  " + "  ".join(f"{t:2d}" for t in tags)
    opsum_ids.append(row_str)

# ============================================================
# Write all files
# ============================================================
out_dir = "H:/moateff_test/config/tiny"
os.makedirs(out_dir, exist_ok=True)

files = {
    "parameters.txt": params,
    "enables.txt": "\n".join(enables) + "\n",
    "ipsum_ln_selectors.txt": "\n".join(ipsum_ln) + "\n",
    "opsum_ln_selectors.txt": "\n".join(opsum_ln) + "\n",
    "ifmap_ids.txt": "\n".join(ifmap_ids) + "\n",
    "filters_ids.txt": "\n".join(filter_ids) + "\n",
    "ipsum_ids.txt": "\n".join(ipsum_ids) + "\n",
    "opsum_ids.txt": "\n".join(opsum_ids) + "\n",
}

for name, content in files.items():
    path = os.path.join(out_dir, name)
    with open(path, "w") as f:
        f.write(content)
    print(f"  {name}")

print(f"\nConfig files written to {out_dir}")

# ============================================================
# Now generate serial_data.txt using the logic from config_script.py
# ============================================================
print("\nGenerating serial_data.txt...")

PARAM_WIDTHS = {
    'H': 8, 'W': 8, 'R': 4, 'S': 4,'E': 6, 'F': 6, 'C': 10, 'M': 10, 'N': 3, 'U': 3,
    'm': 8, 'n': 3, 'e': 6, 'p': 5, 'q': 3, 'r': 2, 't': 3
}

def parse_parameters(lines):
    binary_str = ''
    for line in lines:
        if '=' in line:
            key, val = line.split('=')
            key = key.strip()
            val = int(val.strip())
            width = PARAM_WIDTHS[key]
            binary_str += format(val, f'0{width}b')
    return binary_str

def parse_matrix_to_bits(file_path):
    with open(file_path) as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        bits += ''.join(str(n) for n in nums)
    return bits

def parse_ifmap_ids(file_path):
    with open(file_path) as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        if nums:
            bits += format(nums[0], '04b')
            for num in nums[1:]:
                bits += format(num, '05b')
    return bits

def parse_column_ids(file_path):
    with open(file_path) as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        for num in nums:
            bits += format(num, '04b')
    return bits

# Read and parse
param_lines = [l.strip() for l in params.strip().split('\n') if l.strip()]
parameters = parse_parameters(param_lines)
enables_bits = parse_matrix_to_bits(os.path.join(out_dir, 'enables.txt'))
ipsum_ln_bits = parse_matrix_to_bits(os.path.join(out_dir, 'ipsum_ln_selectors.txt'))
opsum_ln_bits = parse_matrix_to_bits(os.path.join(out_dir, 'opsum_ln_selectors.txt'))
ifmap_bits = parse_ifmap_ids(os.path.join(out_dir, 'ifmap_ids.txt'))
filter_bits = parse_column_ids(os.path.join(out_dir, 'filters_ids.txt'))
ipsum_bits = parse_column_ids(os.path.join(out_dir, 'ipsum_ids.txt'))
opsum_bits = parse_column_ids(os.path.join(out_dir, 'opsum_ids.txt'))

full_chain = parameters + enables_bits + ipsum_ln_bits + opsum_ln_bits + ifmap_bits + filter_bits + ipsum_bits + opsum_bits

# Generate serial_data.txt (reversed bit order, first bit repeated)
serial_path = os.path.join(out_dir, 'serial_data.txt')
reversed_chain = list(reversed(full_chain))
with open(serial_path, 'w') as f:
    if reversed_chain:
        f.write(f'{reversed_chain[0]}\n')
        for bit in reversed_chain:
            f.write(f'{bit}\n')

print(f"  serial_data.txt: {len(full_chain)} bits")
print(f"\nFull chain bit count: {len(full_chain)}")
print(f"  Parameters: {len(parameters)} bits")
print(f"  Enables (12×14): {len(enables_bits)} bits")
print(f"  Ipsum LN sel (12×14): {len(ipsum_ln_bits)} bits")
print(f"  Opsum LN sel (12×14): {len(opsum_ln_bits)} bits")
print(f"  Ifmap IDs (12×15): {len(ifmap_bits)} bits")
print(f"  Filter IDs (12×15): {len(filter_bits)} bits")
print(f"  Ipsum IDs (12×15): {len(ipsum_bits)} bits")
print(f"  Opsum IDs (12×15): {len(opsum_bits)} bits")
print("\nConfig generation complete!")
