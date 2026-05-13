import os

# === Constants ===
PARAM_WIDTHS = {
    'H': 8, 'W': 8, 'R': 4, 'S': 4,'E': 6, 'F': 6, 'C': 10, 'M': 10, 'N': 3, 'U': 3, 
    'm': 8, 'n': 3, 'e': 6, 'p': 5, 'q': 3, 'r': 2, 't': 3
}

INDEX_FOLDER_MAP = {
    1: 'conv1',
    2: 'conv2',
    3: 'conv3',
    4: 'conv4',
    5: 'conv5'
}

# === Utility Functions ===
def read_file_lines(file_path):
    with open(file_path, 'r') as f:
        return [line.strip() for line in f.readlines() if line.strip()]

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
    lines = read_file_lines(file_path)
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        bits += ''.join(str(n) for n in nums)
    return lines, bits

def parse_ifmap_ids(file_path):
    lines = read_file_lines(file_path)
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        if nums:
            bits += format(nums[0], '04b')
            for num in nums[1:]:
                bits += format(num, '05b')
    return lines, bits

def parse_column_ids(file_path):
    lines = read_file_lines(file_path)
    bits = ''
    for line in lines:
        nums = list(map(int, line.split()))
        for num in nums:
            bits += format(num, '04b')
    return lines, bits

# === Main Entry ===
if __name__ == '__main__':
    base_root = os.path.dirname(__file__)

    for user_index, folder_name in INDEX_FOLDER_MAP.items():
        print(f"\nProcessing layer {user_index}: {folder_name}")
        base_dir = os.path.join(base_root, folder_name)

        # File paths
        param_file = os.path.join(base_dir, 'parameters.txt')
        enable_file = os.path.join(base_dir, 'enables.txt')
        ipsum_ln_select_file = os.path.join(base_dir, 'ipsum_ln_selectors.txt')
        opsum_ln_select_file = os.path.join(base_dir, 'opsum_ln_selectors.txt')
        ifmap_file = os.path.join(base_dir, 'ifmap_ids.txt')
        filter_file = os.path.join(base_dir, 'filters_ids.txt')
        ipsum_file = os.path.join(base_dir, 'ipsum_ids.txt')
        opsum_file = os.path.join(base_dir, 'opsum_ids.txt')

        # Ensure files exist
        required_files = [param_file, enable_file, ipsum_ln_select_file, opsum_ln_select_file, ifmap_file, filter_file, ipsum_file, opsum_file]
        for f in required_files:
            if not os.path.exists(f):
                print(f"Skipping {folder_name}: Missing file {os.path.basename(f)}")
                break
        else:
            # Read and parse
            param_lines = read_file_lines(param_file)
            enable_lines, enables = parse_matrix_to_bits(enable_file)
            ipsum_ln_select_lines, ipsum_ln_selectors = parse_matrix_to_bits(ipsum_ln_select_file)
            opsum_ln_select_lines, opsum_ln_selectors = parse_matrix_to_bits(opsum_ln_select_file)
            ifmap_lines, ifmap_ids = parse_ifmap_ids(ifmap_file)
            filter_lines, filters_ids = parse_column_ids(filter_file)
            ipsum_lines, ipsum_ids = parse_column_ids(ipsum_file)
            opsum_lines, opsum_ids = parse_column_ids(opsum_file)
            parameters = parse_parameters(param_lines)

            # === Validation ===
            layer_info = f"(Layer: {folder_name})"
            try:
                assert len(enable_lines) == 12, f"{layer_info} enable_lines must have 12 rows"
                for i, line in enumerate(enable_lines):
                    bits = line.split()
                    assert len(bits) == 14, f"{layer_info} enable_lines row {i} must have 14 elements"
                    assert all(b in {'0', '1'} for b in bits), f"{layer_info} enable_lines row {i} has invalid bits"

                assert len(filter_lines) == 12, f"{layer_info} filter_lines must have 12 rows"
                for i, line in enumerate(filter_lines):
                    nums = list(map(int, line.split()))
                    assert len(nums) == 15, f"{layer_info} filter_lines row {i} must have 15 elements"
                    assert all(0 <= n <= 15 for n in nums), f"{layer_info} filter_lines row {i} out of range"

                assert len(ipsum_lines) == 12, f"{layer_info} ipsum_lines must have 12 rows"
                for i, line in enumerate(ipsum_lines):
                    nums = list(map(int, line.split()))
                    assert len(nums) == 15, f"{layer_info} ipsum_lines row {i} must have 15 elements"
                    assert all(0 <= n <= 15 for n in nums), f"{layer_info} ipsum_lines row {i} out of range"

                assert len(opsum_lines) == 12, f"{layer_info} opsum_lines must have 12 rows"
                for i, line in enumerate(opsum_lines):
                    nums = list(map(int, line.split()))
                    assert len(nums) == 15, f"{layer_info} opsum_lines row {i} must have 15 elements"
                    assert all(0 <= n <= 15 for n in nums), f"{layer_info} opsum_lines row {i} out of range"

                assert len(ifmap_lines) == 12, f"{layer_info} ifmap_lines must have 12 rows"
                for i, line in enumerate(ifmap_lines):
                    nums = list(map(int, line.split()))
                    assert len(nums) == 15, f"{layer_info} ifmap_lines row {i} must have 15 elements"
                    assert 0 <= nums[0] <= 15, f"{layer_info} ifmap_lines row {i} first element out of range"
                    assert all(0 <= n <= 31 for n in nums[1:]), f"{layer_info} ifmap_lines row {i} rest out of range"

                assert len(ipsum_ln_select_lines) == 12, f"{layer_info} ln_select_lines must have 12 rows"
                for i, line in enumerate(ipsum_ln_select_lines):
                    bits = line.split()
                    assert len(bits) == 14, f"{layer_info} ln_select_lines row {i} must have 14 elements"
                    assert all(b in {'0', '1'} for b in bits), f"{layer_info} ln_select_lines row {i} has invalid bits"

                assert len(opsum_ln_select_lines) == 12, f"{layer_info} ln_select_lines must have 12 rows"
                for i, line in enumerate(opsum_ln_select_lines):
                    bits = line.split()
                    assert len(bits) == 14, f"{layer_info} ln_select_lines row {i} must have 14 elements"
                    assert all(b in {'0', '1'} for b in bits), f"{layer_info} ln_select_lines row {i} has invalid bits"

                expected_keys = {'H', 'W', 'R', 'S', 'E', 'F', 'C', 'M', 'N', 'U', 'm', 'n', 'e', 'p', 'q', 'r', 't'}
                found_keys = set()
                for line in param_lines:
                    if '=' in line:
                        key = line.split('=')[0].strip()
                        
                        found_keys.add(key)
                missing_keys = expected_keys - found_keys
                assert not missing_keys, f"{layer_info} parameters.txt is missing keys: {', '.join(missing_keys)}"
            except AssertionError as e:
                print(f"Validation failed for {folder_name}: {e}")
                continue

            # === Output files
            full_chain = parameters + enables + ipsum_ln_selectors + opsum_ln_selectors + ifmap_ids + filters_ids + ipsum_ids + opsum_ids

            scan_chain_path = os.path.join(base_dir, 'scan_chain.txt')
            serial_data_path = os.path.join(base_dir, 'serial_data.txt')

            with open(scan_chain_path, 'w') as f:
                for bit in full_chain:
                    f.write(f'{bit}\n')

            with open(serial_data_path, 'w') as f:
                reversed_chain = list(reversed(full_chain))
                if reversed_chain:
                    f.write(f'{reversed_chain[0]}\n')
                    for bit in reversed_chain:
                        f.write(f'{bit}\n')

            print(f"Successfully generated scan_chain.txt and serial_data.txt in {folder_name}")
