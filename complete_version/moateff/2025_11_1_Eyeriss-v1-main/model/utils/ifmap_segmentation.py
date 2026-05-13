import os

ROWS_PER_SEGMENT = 35
OVERLAP = 7
IMAGE_WIDTH = 227
CHANNELS = 3
TOTAL_ROWS = 227  # Image height

def read_binary_file(filepath):
    with open(filepath, 'r') as file:
        return [line.strip() for line in file.readlines()]

def write_segment_file(filename, data):
    with open(filename, 'w') as f:
        for line in data:
            f.write(line + '\n')

def split_image_lines(all_lines):
    pixels_per_channel = TOTAL_ROWS * IMAGE_WIDTH
    ch1 = all_lines[0 : pixels_per_channel]
    ch2 = all_lines[pixels_per_channel : 2 * pixels_per_channel]
    ch3 = all_lines[2 * pixels_per_channel : 3 * pixels_per_channel]
    return [ch1, ch2, ch3]

def extract_segment_rows(channel_lines, start_row, row_count):
    segment = []
    for i in range(start_row, start_row + row_count):
        if i >= TOTAL_ROWS:
            segment.extend(['0' * 16] * IMAGE_WIDTH)  # Padding
        else:
            start_idx = i * IMAGE_WIDTH
            end_idx = start_idx + IMAGE_WIDTH
            segment.extend(channel_lines[start_idx:end_idx])
    return segment

def main():
    print("=== Segmenting Fixed-Point Binary Image ===")
    input_path = input("Enter path to the binary .txt input file: ").strip()
    output_dir = input("Enter name of output directory (default: segments): ").strip() or "segments"

    if not os.path.exists(input_path):
        print("❌ Input file not found.")
        return

    os.makedirs(output_dir, exist_ok=True)
    lines = read_binary_file(input_path)

    expected_lines = IMAGE_WIDTH * TOTAL_ROWS * CHANNELS
    if len(lines) != expected_lines:
        print(f"❌ Input file should have {expected_lines} lines but found {len(lines)}.")
        return

    channels = split_image_lines(lines)

    start_rows = [0]
    while start_rows[-1] + ROWS_PER_SEGMENT < TOTAL_ROWS:
        start_rows.append(start_rows[-1] + ROWS_PER_SEGMENT - OVERLAP)

    for idx, start in enumerate(start_rows):
        segment_data = []
        for ch in channels:
            segment = extract_segment_rows(ch, start, ROWS_PER_SEGMENT)
            segment_data.extend(segment)
        output_path = os.path.join(output_dir, f"segment_{idx+1}.txt")
        write_segment_file(output_path, segment_data)
        print(f"✅ Written: {output_path}")

if __name__ == "__main__":
    main()
