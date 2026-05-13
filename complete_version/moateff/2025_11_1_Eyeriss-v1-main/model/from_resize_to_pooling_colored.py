#!/usr/bin/env python3
import sys
import numpy as np
from pathlib import Path
from PIL import Image

# ------------------------- Universal Helper Functions -------------------------

def float_to_q313_int16(val: float) -> np.int16:
    """Converts a float in [-8.0, 8.0) to a Q3.13 16-bit signed integer."""
    max_val = (2**15 - 1) / (2**13)
    min_val = -(2**15) / (2**13)
    val = min(max(val, min_val), max_val)
    scaled_val = int(round(val * (2**13)))
    return np.int16(scaled_val)

def int16_to_bin16(x: np.int16) -> str:
    """Converts a signed 16-bit integer to its 16-bit binary string."""
    return format(np.uint16(x).item(), "016b")

def bin16_to_int16(bin_str: str) -> np.int16:
    """Converts a 16-bit binary string to a signed 16-bit integer."""
    val = int(bin_str, 2)
    if val & 0x8000:
        val -= 1 << 16
    return np.int16(val)

def q313_int16_to_float(q_val: np.int16) -> float:
    """Converts a Q3.13 signed 16-bit integer back to a float."""
    return float(q_val) / (2**13)

# ------------------------- Core Pipeline Operations -------------------------

def conv2d_q313(ifmap, weights, biases, kernel_size, stride):
    """Performs a 2D convolution with Q3.13 fixed-point arithmetic."""
    H, W, C = ifmap.shape
    K, _, _, M = weights.shape
    
    OH = (H - K) // stride + 1
    OW = (W - K) // stride + 1
    ofmap = np.zeros((OH, OW, M), dtype=np.int16)

    for m in range(M):
        w_m, b_m = weights[:, :, :, m], biases[m]
        for oh in range(OH):
            for ow in range(OW):
                h, w = oh * stride, ow * stride
                window = ifmap[h:h+K, w:w+K, :]
                mult_res = (window.astype(np.int32) * w_m.astype(np.int32)) >> 13
                acc32 = mult_res.sum() + int(b_m)
                ofmap[oh, ow, m] = np.int16(acc32)
    return ofmap

def apply_relu(data: np.ndarray) -> np.ndarray:
    """Applies the ReLU activation function."""
    return np.maximum(data, np.int16(0))

def max_pooling_3d(input_3d: np.ndarray, pool_size: int, stride: int) -> np.ndarray:
    """Performs 3D max pooling on the input array (H, W, C)."""
    H, W, C = input_3d.shape
    out_H = (H - pool_size) // stride + 1
    out_W = (W - pool_size) // stride + 1
    pooled = np.zeros((out_H, out_W, C), dtype=input_3d.dtype)
    
    for c in range(C):
        for h in range(out_H):
            for w in range(out_W):
                h_start, w_start = h * stride, w * stride
                window = input_3d[h_start:h_start + pool_size, w_start:w_start + pool_size, c]
                pooled[h, w, c] = np.max(window)
    return pooled

# ------------------------- Stage Output & Visualization -------------------------

def save_and_visualize_stage(stage_name: str, data_array: np.ndarray, base_output_dir: Path):
    """Saves the data array of a pipeline stage to .txt and visualizes it as a color .jpg."""
    print(f"--- Processing Stage: {stage_name} ---")
    
    # 1. Create dedicated directory for this stage
    stage_dir = base_output_dir / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)
    
    # 2. Save the raw Q3.13 data to a .txt file
    txt_output_path = stage_dir / f"{stage_name}_output.txt"
    try:
        with txt_output_path.open("w") as f:
            transposed_data = np.transpose(data_array, (2, 0, 1))
            for val in transposed_data.flatten():
                f.write(int16_to_bin16(val) + "\n")
        print(f"✅ Data saved to: {txt_output_path}")
    except IOError as e:
        print(f"❌ Error saving .txt file: {e}")
        return

    # 3. Create and save a .jpg visualization
    jpg_output_path = stage_dir / f"{stage_name}_visualization.jpg"
    try:
        H, W, C = data_array.shape
        float_data = np.vectorize(q313_int16_to_float)(data_array)
        
        # Prepare an empty array for a 3-channel (RGB) image
        pixel_data_rgb = np.zeros((H, W, 3), dtype=np.uint8)

        # For the input image, map its 3 channels directly to RGB
        if C == 3 and stage_name == "0_input":
            # Clip values to be in the valid [0,1] range before scaling
            float_data = np.clip(float_data, 0, 1)
            pixel_data_rgb = (float_data * 255).astype(np.uint8)
        else:
            # For feature maps, map the first 3 channels to R, G, B
            # Normalize each channel individually for best contrast
            if C >= 1: # Map first channel to Red
                r_ch = float_data[:, :, 0]
                min_r, max_r = np.min(r_ch), np.max(r_ch)
                if max_r > min_r: pixel_data_rgb[:, :, 0] = ((r_ch - min_r) / (max_r - min_r) * 255).astype(np.uint8)
            
            if C >= 2: # Map second channel to Green
                g_ch = float_data[:, :, 1]
                min_g, max_g = np.min(g_ch), np.max(g_ch)
                if max_g > min_g: pixel_data_rgb[:, :, 1] = ((g_ch - min_g) / (max_g - min_g) * 255).astype(np.uint8)

            if C >= 3: # Map third channel to Blue
                b_ch = float_data[:, :, 2]
                min_b, max_b = np.min(b_ch), np.max(b_ch)
                if max_b > min_b: pixel_data_rgb[:, :, 2] = ((b_ch - min_b) / (max_b - min_b) * 255).astype(np.uint8)
        
        img = Image.fromarray(pixel_data_rgb, 'RGB')
        img.save(jpg_output_path, 'JPEG')
        print(f"✅ Visualization saved to: {jpg_output_path}")

    except Exception as e:
        print(f"❌ Could not create visualization. Details: {e}")

# ------------------------- Main Orchestrator -------------------------

def main():
    """Main function to run the complete, integrated pipeline."""
    print("🚀 === Full CNN Layer Pipeline: Conv -> ReLU -> Pool === 🚀")
    
    # --- Get Initial User Inputs ---
    image_path = Path(input("Enter the path to the input image: ").strip())
    weights_path = Path(input("Enter path to WEIGHTS .txt file: ").strip())
    biases_path = Path(input("Enter path to BIASES .txt file: ").strip())
    output_dir = Path(input("Enter path for the main OUTPUT directory: ").strip())

    # --- Get Layer Parameters ---
    print("\n--- Enter Convolution Layer Parameters ---")
    try:
        K = int(input("Kernel size (e.g., 11): "))
        S = int(input("Stride (e.g., 4): "))
        M = int(input("Number of filters (output channels): "))
    except ValueError:
        print("❌ Error: Please enter valid integers for convolution parameters.")
        sys.exit(1)

    # --- 1. Process Input Image ---
    print("\n[1] Processing input image...")
    try:
        img_resized = Image.open(image_path).convert('RGB').resize((227, 227), Image.BILINEAR)
        np_img_float = np.array(img_resized).astype(np.float32) / 255.0
        ifmap = np.vectorize(float_to_q313_int16)(np_img_float)
        save_and_visualize_stage("0_input", ifmap, output_dir)
    except Exception as e:
        print(f"❌ Error processing input image: {e}")
        sys.exit(1)

    # --- 2. Load Weights and Biases ---
    print("\n[2] Loading weights and biases...")
    try:
        weights_flat = np.array([bin16_to_int16(line) for line in weights_path.read_text().splitlines() if line.strip()])
        weights = weights_flat.reshape(M, 3, K, K).transpose(2, 3, 1, 0) # Reshape to K,K,C,M
        biases = np.array([bin16_to_int16(line) for line in biases_path.read_text().splitlines() if line.strip()])
        assert biases.shape[0] == M, f"Error: Expected {M} biases but found {biases.shape[0]}."
        print("✅ Weights and biases loaded.")
    except Exception as e:
        print(f"❌ Error loading weights/biases: {e}")
        sys.exit(1)

    # --- 3. Run Convolution ---
    print("\n[3] Running fixed-point convolution...")
    conv_ofmap = conv2d_q313(ifmap, weights, biases, kernel_size=K, stride=S)
    save_and_visualize_stage("1_convolution", conv_ofmap, output_dir)

    # --- 4. Apply ReLU ---
    print("\n[4] Applying ReLU activation...")
    relu_ofmap = apply_relu(conv_ofmap)
    save_and_visualize_stage("2_relu", relu_ofmap, output_dir)
    
    # --- 5. Optional Max Pooling Step ---
    apply_pooling = input("\n[5] Do you want to apply max pooling? (yes/no): ").strip().lower()
    if apply_pooling in ['yes', 'y']:
        print("\n--- Enter Max Pooling Layer Parameters ---")
        try:
            pool_size = int(input("Pooling window size (e.g., 3): "))
            pool_stride = int(input("Pooling stride (e.g., 2): "))
        except ValueError:
            print("❌ Error: Please enter valid integers for pooling parameters.")
            sys.exit(1)
            
        print("\nApplying max pooling...")
        pooled_ofmap = max_pooling_3d(relu_ofmap, pool_size, pool_stride)
        save_and_visualize_stage("3_pooling", pooled_ofmap, output_dir)

    print("\n\n✨ Pipeline finished successfully! Check the output directory. ✨")

if __name__ == "__main__":
    main()