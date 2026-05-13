#!/usr/bin/env python3
"""
Performs the fully-connected network (FCN) stage of AlexNet using
custom Q3.13 fixed-point arithmetic.

This script takes the flattened output of the final convolutional layer,
loads the corresponding ImageNet class names, and prints the top predictions.
"""
import sys
import json
import numpy as np
from pathlib import Path

# --------------------------------------------------------------------
# Universal Fixed-Point and I/O Helper Functions
# --------------------------------------------------------------------

def bin16_to_int16(binstr: str) -> np.int16:
    """Converts a 16-bit two's-complement binary string to a signed 16-bit integer."""
    val = int(binstr, 2)
    if val & 0x8000:
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    """Converts a signed 16-bit integer to a 16-bit two's-complement binary string."""
    return format(np.uint16(x).item(), "016b")

# --------------------------------------------------------------------
# Core Neural Network Layer Implementations
# --------------------------------------------------------------------

def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """
    Element-wise multiplies two Q3.13 int16 arrays with custom bit-preserving truncation.
    """
    prod32 = a.astype(np.int32) * b.astype(np.int32)
    prod32_unsigned = prod32.view(np.uint32)
    
    value_mask = np.uint32(0x0FFFE000)
    sign_mask = np.uint32(0x80000000)
    
    value_part = (prod32_unsigned & value_mask) >> 13
    sign_part = (prod32_unsigned & sign_mask) >> 16
    
    final_result_unsigned = sign_part | value_part
    return final_result_unsigned.astype(np.int16)

def apply_relu(data: np.ndarray) -> np.ndarray:
    """Applies the ReLU activation function to a Q3.13 fixed-point array."""
    return np.maximum(data, np.int16(0))

def fully_connected_layer(input_vector: np.ndarray, weights: np.ndarray, biases: np.ndarray) -> np.ndarray:
    """
    Performs a fully-connected layer operation with custom fixed-point arithmetic.
    """
    n_output = weights.shape[1]
    output_vector = np.zeros(n_output, dtype=np.int64)

    for j in range(n_output):
        weight_col = weights[:, j]
        products = fixed_mul_q313(input_vector, weight_col)
        output_vector[j] = products.astype(np.int64).sum()

    output_vector += biases.astype(np.int64)
    
    INT16_MIN, INT16_MAX = -32768, 32767
    clamped_output = np.clip(output_vector, INT16_MIN, INT16_MAX)
    
    return clamped_output.astype(np.int16)

# --------------------------------------------------------------------
# Main Orchestrator for the FCN
# --------------------------------------------------------------------

def load_fcn_weights(weights_dir: Path):
    """Loads only the fully-connected layer weights and biases."""
    print("\n--- Loading FCN weights and biases ---")
    
    def load_fc(in_feat, out_feat, name):
        w_path = weights_dir / f"{name}_weights.pth.txt"
        b_path = weights_dir / f"{name}_biases.pth.txt"
        
        if not w_path.exists() or not b_path.exists():
            print(f"❌ FATAL ERROR: Weight file not found for {name} at {w_path}", file=sys.stderr)
            sys.exit(1)
            
        w_flat = np.array([bin16_to_int16(line) for line in w_path.read_text().splitlines() if line.strip()])
        weights = w_flat.reshape(out_feat, in_feat).transpose()
        biases = np.array([bin16_to_int16(line) for line in b_path.read_text().splitlines() if line.strip()])
        
        print(f"  - Loaded {name} weights: {weights.shape}, biases: {biases.shape}")
        return weights, biases

    try:
        w = {}
        b = {}
        w['fc1'], b['fc1'] = load_fc(in_feat=9216, out_feat=4096, name='fc_layer_1')
        w['fc2'], b['fc2'] = load_fc(in_feat=4096, out_feat=4096, name='fc_layer_2')
        w['fc3'], b['fc3'] = load_fc(in_feat=4096, out_feat=1000, name='fc_layer_3')
        print("✅ FCN weights and biases loaded successfully.")
        return w, b
    except Exception as e:
        print(f"❌ FATAL ERROR loading weights: {e}", file=sys.stderr)
        sys.exit(1)

def run_fcn_inference(input_vector: np.ndarray, weights: dict, biases: dict):
    """
    Runs the input vector through the full FCN pipeline.
    """
    print("\n--- Running FCN Inference ---")
    
    fc1 = fully_connected_layer(input_vector, weights['fc1'], biases['fc1'])
    relu_fc1 = apply_relu(fc1)
    print("  - FC1 -> ReLU complete.")
    
    fc2 = fully_connected_layer(relu_fc1, weights['fc2'], biases['fc2'])
    relu_fc2 = apply_relu(fc2)
    print("  - FC2 -> ReLU complete.")
    
    fc3_output = fully_connected_layer(relu_fc2, weights['fc3'], biases['fc3'])
    print("  - FC3 (Output Layer) complete.")
    
    return fc3_output

def main():
    """Main execution function."""
    print("🚀 === AlexNet FCN-Only Inference (Custom Fixed-Point) === 🚀")
    
    # --- Get User Inputs ---
    input_file_path = Path(input("Enter path to the INPUT file (e.g., maxpool3_output.txt): ").strip())
    weights_dir = Path(input("Enter path to the WEIGHTS & BIASES directory: ").strip())
    output_file_path = Path(input("Enter path for the final OUTPUT scores file (e.g., final_scores.txt): ").strip())
    class_index_path = Path(input("Enter path to the ImageNet class index JSON file: ").strip())

    # --- Load Class Names ---
    print("\n--- Loading Class Names ---")
    try:
        with class_index_path.open("r") as f:
            # The JSON file is expected to map index to a list: [class_id, class_name]
            # We extract the class name (the second element of the list).
            class_names = {key: value[1] for key, value in json.load(f).items()}
        print(f"✅ Class names loaded successfully for {len(class_names)} classes.")
    except Exception as e:
        print(f"❌ FATAL ERROR loading or parsing class index JSON: {e}", file=sys.stderr)
        sys.exit(1)

    # --- Load Input Data ---
    print(f"\n--- Loading input data from: {input_file_path} ---")
    try:
        input_data = np.array(
            [bin16_to_int16(line) for line in input_file_path.read_text().splitlines() if line.strip()],
            dtype=np.int16
        )
        if input_data.shape[0] != 9216:
            print(f"  ❗️ Warning: Input data shape is {input_data.shape}, expected (9216,).")
        else:
            print(f"  ✅ Input vector loaded successfully with shape: {input_data.shape}")
    except Exception as e:
        print(f"❌ FATAL ERROR loading input file: {e}", file=sys.stderr)
        sys.exit(1)
        
    # --- Load Weights ---
    weights, biases = load_fcn_weights(weights_dir)
    
    # --- Run Inference ---
    final_scores = run_fcn_inference(input_data, weights, biases)
    
    # --- Save Final Output ---
    print(f"\n--- Saving final scores to: {output_file_path} ---")
    try:
        with output_file_path.open("w") as f:
            for score in final_scores:
                f.write(int16_to_bin16(score) + "\n")
        print("✅ Final scores saved successfully.")
        
        # --- Display Top 5 Predictions with Class Names ---
        top5_indices = np.argsort(final_scores)[::-1][:5]
        print("\n" + "="*20 + " TOP 5 PREDICTIONS " + "="*20)
        for i, idx in enumerate(top5_indices):
              marker = "🏆" if i == 0 else f"  {i+1}."
              # Look up the class name using the index
              class_name = class_names.get(str(idx), "Unknown Class")
              # Format the class name for better readability
              formatted_name = class_name.replace('_', ' ').title()
              print(f"{marker} Class: {formatted_name} (Index: {idx}, Score: {final_scores[idx]})")
        print("="*63)
        
    except Exception as e:
        print(f"❌ ERROR saving output file: {e}", file=sys.stderr)
        
if __name__ == "__main__":
    main()