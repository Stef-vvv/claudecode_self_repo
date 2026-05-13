#!/usr/bin/env python3
import sys
import json
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

def apply_padding(data_array: np.ndarray, pad: int) -> np.ndarray:
    """Applies zero-padding to the height and width dimensions of a feature map."""
    if pad == 0:
        return data_array
    return np.pad(data_array, ((pad, pad), (pad, pad), (0, 0)), 'constant', constant_values=0)

# --- INTEGRATED: Custom Bit-Preserving Truncation ---
def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """
    Element-wise multiply two Q3.13 int16 arrays using a custom bit-preserving truncation.

    The final 16-bit result is constructed by selecting specific bits from the
    32-bit Q6.26 intermediate product according to the following rule:
    - New Sign Bit (bit 15):      Taken from product bit 31.
    - New Integer Bits (bits 14-13):  Taken from product bits 27 and 26.
    - New Fractional Bits (bits 12-0): Taken from product bits 25 down to 13.
    """
    # Cast to 32-bit to perform multiplication without overflow.
    prod32 = a.astype(np.int32) * b.astype(np.int32)

    # Use unsigned integers for bitwise operations to prevent overflow errors.
    prod32_unsigned = prod32.view(np.uint32)

    # Define masks as unsigned 32-bit integers.
    value_mask = np.uint32(0x0FFFE000)
    sign_mask = np.uint32(0x80000000)

    # Isolate the value bits and shift them right by 13 to align them in positions 14-0.
    value_part = (prod32_unsigned & value_mask) >> 13

    # Isolate the sign bit and shift it right by 16 to align it in position 15.
    sign_part = (prod32_unsigned & sign_mask) >> 16

    # Combine the sign and value parts. The result is a uint32 array.
    final_result_unsigned = sign_part | value_part

    # Cast the final result to a signed int16. This correctly interprets
    # the two's complement bit pattern of the 16-bit value.
    return final_result_unsigned.astype(np.int16)

# --- INTEGRATED AND ENHANCED FROM CONVOLUTION SCRIPT ---
def conv2d_q313(ifmap, weights, biases, kernel_size, stride):
    """
    Performs a 2D convolution with custom fixed-point arithmetic and saturation.
    """
    H, W, C = ifmap.shape
    K = kernel_size
    _, _, _, M = weights.shape
    OH = (H - K) // stride + 1
    OW = (W - K) // stride + 1
    ofmap = np.zeros((OH, OW, M), dtype=np.int16)

    # Define the min and max values for a 16-bit signed integer for clamping.
    INT16_MIN, INT16_MAX = -32768, 32767

    for m in range(M):
        w_m = weights[:, :, :, m]
        b_m = biases[m]
        for oh in range(OH):
            for ow in range(OW):
                base_h, base_w = oh * stride, ow * stride
                window = ifmap[base_h:base_h+K, base_w:base_w+K, :]
                mult = fixed_mul_q313(window, w_m)
                
                # Sum is done in 32-bit to prevent intermediate overflow.
                acc32 = mult.astype(np.int32).sum() + int(b_m)
                
                # Clamp (saturate) the result to the int16 range to prevent overflow wrap-around.
                clamped_acc = np.clip(acc32, INT16_MIN, INT16_MAX)
                
                ofmap[oh, ow, m] = np.int16(clamped_acc)
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

def fully_connected_layer(input_vector, weights, biases):
    """Performs a fully-connected layer operation."""
    # The multiplication result is scaled back by shifting right by 13.
    # Note: FC layers use standard Q3.13 multiplication, not the custom one.
    output_vector = ((input_vector.astype(np.int32) @ weights.astype(np.int32)) >> 13) + biases.astype(np.int32)
    
    # Clamp the result to the int16 range before casting.
    INT16_MIN, INT16_MAX = -32768, 32767
    clamped_output = np.clip(output_vector, INT16_MIN, INT16_MAX)
    return clamped_output.astype(np.int16)

# ------------------------- Stage Output & Visualization -------------------------

def save_stage_outputs(stage_name: str, data_array: np.ndarray, base_output_dir: Path):
    """
    Saves each channel of a feature map into its own subdirectory, and also
    creates a combined .txt file and a grid visualization for all channels.
    """
    print(f"--- Processing Stage: {stage_name} ---")
    
    stage_dir = base_output_dir / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)
    
    if data_array.ndim != 3:
        print(f"     - Data is not a 3D tensor (shape: {data_array.shape}). Skipping detailed channel output.")
        return

    H, W, C = data_array.shape
    print(f"     - Feature map shape: ({H}, {W}, {C}).")

    # Part 1: Save each channel individually and collect images for the grid
    print(f"     - Saving {C} individual channel output(s)...")
    channel_images = []
    for c in range(C):
        channel_data = data_array[:, :, c]
        channel_dir = stage_dir / f"channel_{c:03d}"
        channel_dir.mkdir(exist_ok=True)

        txt_output_path = channel_dir / "output.txt"
        with txt_output_path.open("w") as f:
            for val in channel_data.flatten():
                f.write(int16_to_bin16(val) + "\n")

        jpg_output_path = channel_dir / "visualization.jpeg"
        float_channel = np.vectorize(q313_int16_to_float)(channel_data)
        
        min_val, max_val = np.min(float_channel), np.max(float_channel)
        if max_val > min_val:
            normalized_data = ((float_channel - min_val) / (max_val - min_val) * 255)
        else:
            normalized_data = np.zeros_like(float_channel)
            
        img = Image.fromarray(normalized_data.astype(np.uint8), 'L')
        img.save(jpg_output_path, 'JPEG')
        channel_images.append(img)
        
    # Part 2: Save the combined .txt file for all channels
    print("     - Saving combined .txt for all channels...")
    combined_txt_path = stage_dir / f"{stage_name}_all_channels.txt"
    with combined_txt_path.open("w") as f:
        for c in range(C):
            for val in data_array[:, :, c].flatten():
                f.write(int16_to_bin16(val) + "\n")

    # Part 3: Create and save the combined grid visualization
    if C > 0 and H > 0 and W > 0:
        print("     - Creating and saving grid visualization...")
        grid_cols = int(np.ceil(np.sqrt(C)))
        grid_rows = int(np.ceil(C / grid_cols))
        
        canvas_width = grid_cols * W
        canvas_height = grid_rows * H
        grid_image = Image.new('L', (canvas_width, canvas_height))

        for i, img in enumerate(channel_images):
            row = i // grid_cols
            col = i % grid_cols
            grid_image.paste(img, (col * W, row * H))

        grid_jpg_path = stage_dir / f"{stage_name}_visualization_grid.jpeg"
        grid_image.save(grid_jpg_path, 'JPEG')
        
    print(f"✅ Stage '{stage_name}' saved successfully.")

def save_fc_output(stage_name: str, data_vector: np.ndarray, base_output_dir: Path):
    """Saves the output vector of a fully-connected layer to a .txt file."""
    print(f"--- Processing Stage: {stage_name} ---")
    stage_dir = base_output_dir / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)
    
    txt_output_path = stage_dir / f"{stage_name}_output.txt"
    with txt_output_path.open("w") as f:
        for val in data_vector:
            f.write(int16_to_bin16(val) + "\n")
    print(f"✅ Data saved to: {txt_output_path}")

# ------------------------- Main Orchestrator -------------------------

def load_conv_files(w_path: Path, b_path: Path, M: int, C: int, K: int):
    """Loads and reshapes weights and biases for a convolutional layer."""
    print(f"Loading weights from {w_path.name} and biases from {b_path.name}...")
    try:
        w_flat = np.array([bin16_to_int16(line) for line in w_path.read_text().splitlines() if line.strip()])
        weights = w_flat.reshape(M, C, K, K).transpose(2, 3, 1, 0)
        biases = np.array([bin16_to_int16(line) for line in b_path.read_text().splitlines() if line.strip()])
        assert biases.shape[0] == M, f"Expected {M} biases but found {biases.shape[0]}."
        return weights, biases
    except Exception as e:
        print(f"❌ Error loading conv files for M={M}, C={C}, K={K}. Details: {e}", file=sys.stderr)
        sys.exit(1)

def load_fc_files(w_path: Path, b_path: Path, input_features: int, output_features: int):
    """Loads and reshapes weights and biases for a fully-connected layer."""
    print(f"Loading weights from {w_path.name} and biases from {b_path.name}...")
    try:
        w_flat = np.array([bin16_to_int16(line) for line in w_path.read_text().splitlines() if line.strip()])
        weights = w_flat.reshape(output_features, input_features).transpose()
        biases = np.array([bin16_to_int16(line) for line in b_path.read_text().splitlines() if line.strip()])
        assert biases.shape[0] == output_features, f"Expected {output_features} biases but found {biases.shape[0]}."
        return weights, biases
    except Exception as e:
        print(f"❌ Error loading FC files for In={input_features}, Out={output_features}. Details: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    print("🚀 === AlexNet Batch Forward Pass Simulation (Custom Truncation) === 🚀")
    
    # --- Get All Necessary Inputs ---
    print("\n--- Please provide paths to all necessary files ---")
    image_dir = Path(input("Enter path to the INPUT IMAGE DIRECTORY: ").strip())
    output_dir = Path(input("Enter path for the main OUTPUT DIRECTORY: ").strip())
    class_index_path = Path(input("Enter path to the ImageNet class index JSON file: ").strip())
    
    # --- Load all weights and configuration files ONCE ---
    print("\n--- Loading all model weights and configuration files ---")
    w1_path = Path(input("Enter path to WEIGHTS file for CONV1: ").strip())
    b1_path = Path(input("Enter path to BIASES file for CONV1: ").strip())
    w2_path = Path(input("Enter path to WEIGHTS file for CONV2: ").strip())
    b2_path = Path(input("Enter path to BIASES file for CONV2: ").strip())
    w3_path = Path(input("Enter path to WEIGHTS file for CONV3: ").strip())
    b3_path = Path(input("Enter path to BIASES file for CONV3: ").strip())
    w4_path = Path(input("Enter path to WEIGHTS file for CONV4: ").strip())
    b4_path = Path(input("Enter path to BIASES file for CONV4: ").strip())
    w5_path = Path(input("Enter path to WEIGHTS file for CONV5: ").strip())
    b5_path = Path(input("Enter path to BIASES file for CONV5: ").strip())
    w6_path = Path(input("Enter path to WEIGHTS file for FC6: ").strip())
    b6_path = Path(input("Enter path to BIASES file for FC6: ").strip())
    w7_path = Path(input("Enter path to WEIGHTS file for FC7: ").strip())
    b7_path = Path(input("Enter path to BIASES file for FC7: ").strip())
    w8_path = Path(input("Enter path to WEIGHTS file for FC8: ").strip())
    b8_path = Path(input("Enter path to BIASES file for FC8: ").strip())

    # --- Load Class Names ---
    try:
        with class_index_path.open("r") as f:
            class_names = {key: value[1] for key, value in json.load(f).items()}
        print("✅ Class names loaded successfully.")
    except Exception as e:
        print(f"❌ Error loading or parsing class index JSON: {e}", file=sys.stderr)
        sys.exit(1)

    # --- Load all weights into memory ---
    w1, b1 = load_conv_files(w1_path, b1_path, M=64, C=3, K=11)
    w2, b2 = load_conv_files(w2_path, b2_path, M=192, C=64, K=5)
    w3, b3 = load_conv_files(w3_path, b3_path, M=384, C=192, K=3)
    w4, b4 = load_conv_files(w4_path, b4_path, M=256, C=384, K=3)
    w5, b5 = load_conv_files(w5_path, b5_path, M=256, C=256, K=3)
    w6, b6 = load_fc_files(w6_path, b6_path, input_features=9216, output_features=4096)
    w7, b7 = load_fc_files(w7_path, b7_path, input_features=4096, output_features=4096)
    w8, b8 = load_fc_files(w8_path, b8_path, input_features=4096, output_features=1000)
    
    # --- Diagnostic Check ---
    if not image_dir.is_dir():
        print(f"❌ FATAL ERROR: Input directory not found at '{image_dir}'", file=sys.stderr)
        sys.exit(1)
    image_files = list(image_dir.glob('*.jpg')) + list(image_dir.glob('*.png')) + list(image_dir.glob('*.jpeg'))
    if not image_files:
        print(f"❌ FATAL ERROR: No images found in '{image_dir}'", file=sys.stderr)
        sys.exit(1)
    print(f"\n✅ Diagnostic OK: Found {len(image_files)} images to process.")

    # --- Main loop to process each image ---
    for image_path in image_files:
        print(f"\n\n{'='*25} Processing Image: {image_path.name} {'='*25}")
        image_output_dir = output_dir / image_path.stem
        step = 0
        try:
            # --- STAGE 0: Input ---
            img = Image.open(image_path).convert('RGB').resize((227, 227), Image.Resampling.BILINEAR)
            ifmap = np.vectorize(float_to_q313_int16)(np.array(img).astype(np.float32) / 255.0)
            save_stage_outputs(f"{step:02d}_input", ifmap, image_output_dir); step += 1
            
            # --- LAYER 1 ---
            conv1 = conv2d_q313(ifmap, w1, b1, kernel_size=11, stride=4)
            save_stage_outputs(f"{step:02d}_conv1", conv1, image_output_dir); step += 1
            relu1 = apply_relu(conv1)
            save_stage_outputs(f"{step:02d}_relu1", relu1, image_output_dir); step += 1
            max1 = max_pooling_3d(relu1, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool1", max1, image_output_dir); step += 1
            
            # --- LAYER 2 ---
            pad1 = apply_padding(max1, pad=2)
            conv2 = conv2d_q313(pad1, w2, b2, kernel_size=5, stride=1)
            save_stage_outputs(f"{step:02d}_conv2", conv2, image_output_dir); step += 1
            relu2 = apply_relu(conv2)
            save_stage_outputs(f"{step:02d}_relu2", relu2, image_output_dir); step += 1
            max2 = max_pooling_3d(relu2, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool2", max2, image_output_dir); step += 1
            
            # --- LAYER 3 ---
            pad2 = apply_padding(max2, pad=1)
            conv3 = conv2d_q313(pad2, w3, b3, kernel_size=3, stride=1)
            save_stage_outputs(f"{step:02d}_conv3", conv3, image_output_dir); step += 1
            relu3 = apply_relu(conv3)
            save_stage_outputs(f"{step:02d}_relu3", relu3, image_output_dir); step += 1
            
            # --- LAYER 4 ---
            pad3 = apply_padding(relu3, pad=1)
            conv4 = conv2d_q313(pad3, w4, b4, kernel_size=3, stride=1)
            save_stage_outputs(f"{step:02d}_conv4", conv4, image_output_dir); step += 1
            relu4 = apply_relu(conv4)
            save_stage_outputs(f"{step:02d}_relu4", relu4, image_output_dir); step += 1
            
            # --- LAYER 5 ---
            pad4 = apply_padding(relu4, pad=1)
            conv5 = conv2d_q313(pad4, w5, b5, kernel_size=3, stride=1)
            save_stage_outputs(f"{step:02d}_conv5", conv5, image_output_dir); step += 1
            relu5 = apply_relu(conv5)
            save_stage_outputs(f"{step:02d}_relu5", relu5, image_output_dir); step += 1
            max3 = max_pooling_3d(relu5, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool3", max3, image_output_dir); step += 1
            
            # --- Flatten & FC Layers ---
            flattened_vector = max3.flatten()
            fc6 = fully_connected_layer(flattened_vector, w6, b6)
            save_fc_output(f"{step:02d}_fc6", fc6, image_output_dir); step += 1
            relu6 = apply_relu(fc6)
            save_fc_output(f"{step:02d}_relu6", relu6, image_output_dir); step += 1
            fc7 = fully_connected_layer(relu6, w7, b7)
            save_fc_output(f"{step:02d}_fc7", fc7, image_output_dir); step += 1
            relu7 = apply_relu(fc7)
            save_fc_output(f"{step:02d}_relu7", relu7, image_output_dir); step += 1
            fc8 = fully_connected_layer(relu7, w8, b8)
            save_fc_output(f"{step:02d}_fc8_output", fc8, image_output_dir); step += 1

            # --- Final Prediction ---
            top5_indices = np.argsort(fc8)[::-1][:5]
            print("\n" + "="*20 + f" TOP 5 PREDICTIONS FOR: {image_path.name} " + "="*20)
            for i, idx in enumerate(top5_indices):
                class_name = class_names.get(str(idx), "Unknown Class")
                marker = "🏆" if i == 0 else f"  {i+1}."
                print(f"{marker} Class: {class_name.replace('_', ' ').title()} (Index: {idx}, Score: {fc8[idx]})")
            print("="*70)

        except Exception as e:
            print(f"\n❌ An error occurred while processing {image_path.name}: {e}", file=sys.stderr)
            print("  Skipping to the next image.", file=sys.stderr)

    print("\n\n✨ AlexNet batch processing finished successfully! ✨")

if __name__ == "__main__":
    main()
