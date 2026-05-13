import numpy as np
from pathlib import Path

def bin16_to_int16(binstr: str) -> np.int16:
    """Convert 16-bit two's complement binary string to int16"""
    val = int(binstr, 2)
    return np.int16(val - (1 << 16) if val & 0x8000 else val)

def int16_to_bin16(x: np.int16) -> str:
    """Convert int16 to 16-bit two's complement binary string"""
    return format(np.uint16(x).item(), "016b")

def load_conv_output(file_path: Path) -> np.ndarray:
    """Load convolution output file into (55, 55, 64) int16 array"""
    with file_path.open("r") as f:
        data = np.array([bin16_to_int16(line.strip()) for line in f], dtype=np.int16)
    return data.reshape(31, 31, 64)  # Reshape to Conv1 output dimensions

def apply_relu(data: np.ndarray) -> np.ndarray:
    """Apply ReLU activation (set negatives to zero)"""
    return np.maximum(data, np.int16(0))

def save_relu_output(data: np.ndarray, output_path: Path):
    """Save ReLU output in same binary format as input"""
    with output_path.open("w") as f:
        for val in data.flatten():
            f.write(int16_to_bin16(val) + "\n")

def main(input_file: str, output_file: str):
    """Main processing pipeline"""
    # Load convolution output
    conv_output = load_conv_output(Path(input_file))
    
    print(f"Loaded convolution output with shape {conv_output.shape}")
    print(f"Pre-ReLU range: [{np.min(conv_output)}, {np.max(conv_output)}]")
    
    # Apply ReLU
    relu_output = apply_relu(conv_output)
    
    print(f"Post-ReLU range: [{np.min(relu_output)}, {np.max(relu_output)}]")
    print(f"Zeroed values: {np.sum(relu_output == 0)/relu_output.size:.1%}")
    
    # Save results
    save_relu_output(relu_output, Path(output_file))
    print(f"ReLU output saved to {output_file}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python apply_relu.py CONV_OUTPUT.txt RELU_OUTPUT.txt")
        sys.exit(1)
    
    main(sys.argv[1], sys.argv[2])