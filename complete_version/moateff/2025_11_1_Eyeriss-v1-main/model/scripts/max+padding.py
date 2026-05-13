import numpy as np
import os

def binary_to_q313(binary_str):
    """
    Convert 16-bit binary string (Q3.13 format) to signed integer.
    Args:
        binary_str: 16-bit binary string
    Returns:
        int: Signed integer value
    """
    if len(binary_str) != 16:
        raise ValueError(f"Binary string must be 16 bits, got {len(binary_str)}")
    if binary_str[0] == '1':  # Negative number
        return -(int(''.join('1' if b == '0' else '0' for b in binary_str), 2) + 1)
    return int(binary_str, 2)

def q313_to_binary(value):
    """
    Convert integer back to 16-bit Q3.13 binary string.
    Args:
        value: Integer value to convert
    Returns:
        str: 16-bit binary string
    """
    if value < 0:  # Two's complement for negative numbers
        return bin((abs(value) ^ 0xFFFF) + 1)[2:].zfill(16)
    return bin(value)[2:].zfill(16)

def read_input_binary(file_path, H, W, C):
    """
    Read binary input file and reshape to (H, W, C)
    Args:
        file_path: Path to input file
        H: Height dimension
        W: Width dimension
        C: Channels dimension
    Returns:
        numpy.ndarray: Reshaped array of integers
    """
    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    
    if len(lines) != H * W * C:
        raise ValueError(f"Expected {H*W*C} values, got {len(lines)}")
    
    data = [binary_to_q313(line) if len(line) == 16 else 0 for line in lines]
    return np.array(data, dtype=int).reshape(H, W, C)

import numpy as np

def max_pooling_3d(input_3d, pool_size=3, stride=2, padding=2):
    """
    Apply max pooling first, then padding on 3D input (H, W, C)

    Args:
        input_3d: Input array of shape (H, W, C)
        pool_size: Size of the max pooling window
        stride: Stride of the max pooling operation
        padding: Padding to apply after pooling

    Returns:
        numpy.ndarray: Result after max pooling and then padding
    """
    H, W, C = input_3d.shape

    # Calculate output dimensions for max pooling
    out_H = (H - pool_size) // stride + 1
    out_W = (W - pool_size) // stride + 1

    pooled = np.zeros((out_H, out_W, C), dtype=input_3d.dtype)

    for c in range(C):
        for h in range(out_H):
            for w in range(out_W):
                h_start = h * stride
                w_start = w * stride
                window = input_3d[h_start:h_start + pool_size,
                                  w_start:w_start + pool_size,
                                  c]
                pooled[h, w, c] = np.max(window)

    # Apply padding after pooling
    padded = np.pad(pooled,
                    ((padding, padding), (padding, padding), (0, 0)),
                    mode='constant',
                    constant_values=0)

    return padded

'''
def max_pooling_3d(input_3d, pool_size=3, stride=2, padding=2):
    """
    Perform max pooling on 3D input (H, W, C)
    Args:
        input_3d: Input array (H, W, C)
        pool_size: Pooling window size
        stride: Stride for pooling
        padding: Padding size
    Returns:
        numpy.ndarray: Pooled output
    """
    H, W, C = input_3d.shape
    # Apply padding
    padded = np.pad(input_3d, 
                   ((padding, padding), (padding, padding), (0, 0)),
                   mode='constant',
                   constant_values=0)
    
    # Calculate output dimensions
    out_H = (H + 2*padding - pool_size) // stride + 1
    out_W = (W + 2*padding - pool_size) // stride + 1
    
    output = np.zeros((out_H, out_W, C), dtype=int)
    
    for c in range(C):
        for h in range(out_H):
            for w in range(out_W):
                h_start = h * stride
                w_start = w * stride
                window = padded[h_start:h_start+pool_size, 
                               w_start:w_start+pool_size, 
                               c]
                output[h, w, c] = np.max(window)
    
    return output
'''
def write_output_binary(output, file_path):
    """
    Write output array to file as binary strings
    Args:
        output: Array to save
        file_path: Output file path
    """
    flattened = output.flatten()
    with open(file_path, 'w') as f:
        for value in flattened:
            f.write(q313_to_binary(value) + '\n')

def read_parameters(param_file):
    """
    Read parameters from file
    Args:
        param_file: Path to parameter file
    Returns:
        dict: Dictionary of parameters
    """
    params = {}
    with open(param_file, 'r') as f:
        for line in f:
            if line.strip():
                key, val = line.strip().split()
                params[key] = int(val)
    return params

def main():
    # Get current directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Get file paths
    input_file = input("Enter input binary file name: ").strip()
    param_file = input("Enter parameter file name: ").strip()
    
    input_path = os.path.join(script_dir, input_file)
    param_path = os.path.join(script_dir, param_file)
    
    try:
        # Read parameters
        params = read_parameters(param_path)
        H, W, C = params['H'], params['W'], params['C']
        pool_size = params.get('pool_size', 3)
        stride = params.get('stride', 2)
        padding = params.get('padding', 2)
        
        # Read and validate input
        input_3d = read_input_binary(input_path, H, W, C)
        print(f"Input shape: {input_3d.shape}")
        
        # Perform max pooling
        output = max_pooling_3d(input_3d, pool_size, stride, padding)
        print(f"Output shape: {output.shape}")
        
        # Write output
        output_path = os.path.join(script_dir, "max_1_output.txt")
        write_output_binary(output, output_path)
        print(f"Output saved to {output_path}")
        
    except FileNotFoundError as e:
        print(f"File not found: {e}")
    except ValueError as e:
        print(f"Value error: {e}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()