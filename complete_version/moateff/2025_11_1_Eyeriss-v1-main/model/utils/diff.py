def compare_and_show_differences(file1_path, file2_path):
    with open(file1_path, 'r') as f1, open(file2_path, 'r') as f2:
        lines1 = f1.readlines()
        lines2 = f2.readlines()

    max_len = max(len(lines1), len(lines2))
    mismatch_count = 0

    for i in range(max_len):
        line1 = lines1[i].rstrip('\n') if i < len(lines1) else '<missing>'
        line2 = lines2[i].rstrip('\n') if i < len(lines2) else '<missing>'

        if line1 != line2:
            mismatch_count += 1
            print(f"Line {i + 1}:")
            print(f"  File1: {line1}")
            print(f"  File2: {line2}")
            print()

    if mismatch_count == 0:
        print("🏆 All lines matched successfully!")
    else:
        print(f"Total mismatched lines: {mismatch_count}")

def main():
    import sys
    if len(sys.argv) != 3:
        print("Usage: python diff_script.py <file1.txt> <file2.txt>")
        return

    file1_path = sys.argv[1]
    file2_path = sys.argv[2]
    compare_and_show_differences(file1_path, file2_path)

if __name__ == "__main__":
    main()
