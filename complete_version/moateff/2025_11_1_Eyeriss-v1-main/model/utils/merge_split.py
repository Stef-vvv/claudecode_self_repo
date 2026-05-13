import os

def split_64bit_to_4x16bit(word_64):
    """Splits a 64-bit word into 4x16-bit words."""
    word_64 = word_64.replace('-', '')
    if len(word_64) != 64:
        raise ValueError(f"Input word must be exactly 64 bits. Got: {len(word_64)} bits.")
    words = [word_64[i:i+16] for i in range(0, 64, 16)]
    return words[::-1]  # Return as word0 to word3

def merge_4x16bit_to_64bit(words_16):
    """Merges 4x16-bit binary strings into one 64-bit string."""
    if len(words_16) != 4 or any(len(w) != 16 for w in words_16):
        raise ValueError("Input must be a list of four 16-bit binary strings.")
    return ''.join(words_16[::-1])

def process_file(input_path, mode):
    with open(input_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    output_lines = []

    if mode == 'S':
        for line in lines:
            output_lines.extend(split_64bit_to_4x16bit(line))
        output_path = os.path.splitext(input_path)[0] + '_16bit_split.txt'

    elif mode == 'M':
        remainder = len(lines) % 4
        if remainder != 0:
            padding = 4 - remainder
            print(f"[!] Padding with {padding} zeros to make line count divisible by 4.")
            lines.extend(['0' * 16] * padding)

        for i in range(0, len(lines), 4):
            output_lines.append(merge_4x16bit_to_64bit(lines[i:i+4]))
        output_path = os.path.splitext(input_path)[0] + '_64bit_merged.txt'

    else:
        raise ValueError("Mode must be 'S' (split) or 'M' (merge).")

    with open(output_path, 'w') as f:
        for line in output_lines:
            f.write(line + '\n')

    print(f"✅ Output written to: {output_path}")

def main():
    print("=== Binary Word Split / Merge Tool ===")
    input_path = input("Enter path to input .txt file: ").strip()
    if not os.path.isfile(input_path):
        print("❌ Error: file not found.")
        return

    mode = input("Enter mode: [S] for split, [M] for merge: ").strip().upper()
    if mode not in ['S', 'M']:
        print("❌ Invalid mode. Use 'S' for split or 'M' for merge.")
        return

    try:
        process_file(input_path, mode)
    except Exception as e:
        print(f"[!] Error: {e}")

if __name__ == '__main__':
    main()
