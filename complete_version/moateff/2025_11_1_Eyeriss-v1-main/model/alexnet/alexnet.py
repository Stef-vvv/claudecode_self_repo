#!/usr/bin/env python3
"""
Performs a full, end-to-end simulation of the AlexNet neural network using
custom Q3.13 fixed-point arithmetic with bit-preserving truncation.

The script processes a batch of images and generates a highly detailed, organized
output for each stage of the network, allowing for in-depth analysis and debugging.
"""
import sys
import json
import numpy as np
from pathlib import Path
from PIL import Image

# --------------------------------------------------------------------
# Universal Fixed-Point and I/O Helper Functions
# --------------------------------------------------------------------

def float_to_q313_int16(val: float) -> np.int16:
    """Converts a float in [-8.0, 8.0) to a Q3.13 16-bit signed integer."""
    max_val = (2**15 - 1) / (2**13)
    min_val = -(2**15) / (2**13)
    val = min(max(val, min_val), max_val)
    scaled_val = int(round(val * (2**13)))
    return np.int16(scaled_val)

def bin16_to_int16(binstr: str) -> np.int16:
    """Converts a 16-bit two's-complement binary string to int16."""
    val = int(binstr, 2)
    if val & 0x8000:
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    """Converts int16 to a 16-bit two's-complement binary string."""
    return format(np.uint16(x).item(), "016b")

def q313_int16_to_float(q_val: np.int16) -> float:
    """Converts a Q3.13 signed 16-bit integer back to a float for visualization."""
    return float(q_val) / (2**13)

# --------------------------------------------------------------------
# Core Neural Network Layer Implementations
# --------------------------------------------------------------------

def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """
    Element-wise multiply two Q3.13 int16 arrays using custom bit-preserving truncation.
    - New Sign Bit (bit 15):      Taken from product bit 31.
    - New Integer Bits (bits 14-13):  Taken from product bits 27 and 26.
    - New Fractional Bits (bits 12-0): Taken from product bits 25 down to 13.
    """
    prod32 = a.astype(np.int32) * b.astype(np.int32)
    prod32_unsigned = prod32.view(np.uint32)
    value_mask = np.uint32(0x0FFFE000)
    sign_mask = np.uint32(0x80000000)
    value_part = (prod32_unsigned & value_mask) >> 13
    sign_part = (prod32_unsigned & sign_mask) >> 16
    final_result_unsigned = sign_part | value_part
    return final_result_unsigned.astype(np.int16)

def conv2d_q313(ifmap, weights, biases, stride):
    """Performs a 2D convolution with custom fixed-point arithmetic and saturation."""
    H, W, C = ifmap.shape
    K, _, _, M = weights.shape
    OH = (H - K) // stride + 1
    OW = (W - K) // stride + 1
    ofmap = np.zeros((OH, OW, M), dtype=np.int16)
    INT16_MIN, INT16_MAX = -32768, 32767

    for m in range(M):
        w_m = weights[:, :, :, m]
        b_m = biases[m]
        for oh in range(OH):
            for ow in range(OW):
                base_h, base_w = oh * stride, ow * stride
                window = ifmap[base_h:base_h+K, base_w:base_w+K, :]
                mult = fixed_mul_q313(window, w_m)
                acc32 = mult.astype(np.int32).sum() + int(b_m)
                clamped_acc = np.clip(acc32, INT16_MIN, INT16_MAX)
                ofmap[oh, ow, m] = np.int16(clamped_acc)
    return ofmap

def apply_padding(data_array: np.ndarray, pad: int) -> np.ndarray:
    """Applies zero-padding to the height and width dimensions of a feature map."""
    if pad == 0:
        return data_array
    return np.pad(data_array, ((pad, pad), (pad, pad), (0, 0)), 'constant', constant_values=0)

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
    """Performs a fully-connected layer operation with custom bit-preserving truncation."""
    n_output = weights.shape[1]
    output_vector = np.zeros(n_output, dtype=np.int64)

    # Manually compute the matrix multiplication (dot product) for each output neuron
    # to ensure the custom multiplication is applied before summation.
    for j in range(n_output):
        # Get the weights for the j-th output neuron
        weight_col = weights[:, j]
        
        # Perform element-wise multiplication with the custom fixed-point function
        products = fixed_mul_q313(input_vector, weight_col)
        
        # Sum the results in a 64-bit accumulator
        output_vector[j] = products.astype(np.int64).sum()

    # Add the biases
    output_vector += biases.astype(np.int64)
    
    # Clamp the final result to the int16 range
    INT16_MIN, INT16_MAX = -32768, 32767
    clamped_output = np.clip(output_vector, INT16_MIN, INT16_MAX)
    return clamped_output.astype(np.int16)

# --------------------------------------------------------------------
# Output Generation and Visualization
# --------------------------------------------------------------------

def save_stage_outputs(stage_name: str, data_array: np.ndarray, base_output_dir: Path):
    """Saves comprehensive outputs for a convolutional or pooling stage."""
    print(f"--- Saving Stage: {stage_name} ---")
    stage_dir = base_output_dir / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)
    
    if data_array.ndim != 3:
        print(f"  ❗️Warning: Data is not a 3D tensor (shape: {data_array.shape}). Skipping detailed output.")
        return

    H, W, C = data_array.shape
    print(f"  - Feature map shape: ({H}, {W}, {C}).")

    # Save combined .txt file for all channels
    combined_txt_path = stage_dir / f"{stage_name}_all_channels.txt"
    with combined_txt_path.open("w") as f:
        for c in range(C):
            for val in data_array[:, :, c].flatten():
                f.write(int16_to_bin16(val) + "\n")

    # Save individual channels and create grid visualization
    channel_images = []
    for c in range(C):
        channel_data = data_array[:, :, c]
        channel_dir = stage_dir / f"channel_{c:03d}"
        channel_dir.mkdir(exist_ok=True)

        txt_output_path = channel_dir / "output.txt"
        with txt_output_path.open("w") as f:
            for val in channel_data.flatten():
                f.write(int16_to_bin16(val) + "\n")

        float_channel = np.vectorize(q313_int16_to_float)(channel_data)
        min_val, max_val = np.min(float_channel), np.max(float_channel)
        normalized_data = ((float_channel - min_val) / (max_val - min_val) * 255) if max_val > min_val else np.zeros_like(float_channel)
        img = Image.fromarray(normalized_data.astype(np.uint8), 'L')
        
        jpg_output_path = channel_dir / "visualization.jpeg"
        img.save(jpg_output_path, 'JPEG')
        channel_images.append(img)
        
    if C > 0 and H > 0 and W > 0:
        grid_cols = int(np.ceil(np.sqrt(C)))
        grid_rows = int(np.ceil(C / grid_cols))
        grid_image = Image.new('L', (grid_cols * W, grid_rows * H))
        for i, img in enumerate(channel_images):
            grid_image.paste(img, ((i % grid_cols) * W, (i // grid_cols) * H))
        grid_jpg_path = stage_dir / f"{stage_name}_visualization_grid.jpeg"
        grid_image.save(grid_jpg_path, 'JPEG')
        
    print(f"  ✅ Stage '{stage_name}' saved successfully.")

def save_fc_output(stage_name: str, data_vector: np.ndarray, base_output_dir: Path):
    """Saves the output vector of a fully-connected layer."""
    print(f"--- Saving Stage: {stage_name} ---")
    stage_dir = base_output_dir / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)
    txt_output_path = stage_dir / f"{stage_name}_output.txt"
    with txt_output_path.open("w") as f:
        for val in data_vector:
            f.write(int16_to_bin16(val) + "\n")
    print(f"  ✅ Data saved to: {txt_output_path}")

# --------------------------------------------------------------------
# Main Orchestrator
# --------------------------------------------------------------------

def load_weights(weights_dir: Path):
    """Loads all model weights and biases from the specified directory."""
    print("\n--- Loading all model weights and biases ---")
    
    def load_conv(C, M, K, name):
        w_path = weights_dir / f"{name}_filter_16.txt"
        b_path = weights_dir / f"{name}_bias_16.txt"
        w_flat = np.array([bin16_to_int16(line) for line in w_path.read_text().splitlines() if line.strip()])
        weights = w_flat.reshape(M, C, K, K).transpose(2, 3, 1, 0)
        biases = np.array([bin16_to_int16(line) for line in b_path.read_text().splitlines() if line.strip()])
        print(f"  - Loaded {name} weights: {weights.shape}, biases: {biases.shape}")
        return weights, biases

    def load_fc(in_feat, out_feat, name):
        w_path = weights_dir / f"{name}_weights.pth.txt"
        b_path = weights_dir / f"{name}_biases.pth.txt"
        w_flat = np.array([bin16_to_int16(line) for line in w_path.read_text().splitlines() if line.strip()])
        weights = w_flat.reshape(out_feat, in_feat).transpose()
        biases = np.array([bin16_to_int16(line) for line in b_path.read_text().splitlines() if line.strip()])
        print(f"  - Loaded {name} weights: {weights.shape}, biases: {biases.shape}")
        return weights, biases

    try:
        w = {}
        b = {}
        w['conv1'], b['conv1'] = load_conv(C=3, M=64, K=11, name='conv1')
        w['conv2'], b['conv2'] = load_conv(C=64, M=192, K=5, name='conv2')
        w['conv3'], b['conv3'] = load_conv(C=192, M=384, K=3, name='conv3')
        w['conv4'], b['conv4'] = load_conv(C=384, M=256, K=3, name='conv4')
        w['conv5'], b['conv5'] = load_conv(C=256, M=256, K=3, name='conv5')
        w['fc1'], b['fc1'] = load_fc(in_feat=9216, out_feat=4096, name='fc_layer_1')
        w['fc2'], b['fc2'] = load_fc(in_feat=4096, out_feat=4096, name='fc_layer_2')
        w['fc3'], b['fc3'] = load_fc(in_feat=4096, out_feat=1000, name='fc_layer_3')
        print("✅ All weights and biases loaded successfully.")
        return w, b
    except Exception as e:
        print(f"❌ FATAL ERROR loading weights: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    print("🚀 === AlexNet Full Pipeline Simulation (Custom Fixed-Point) === 🚀")
    
    # --- Get User Inputs ---
    image_dir = Path(input("Enter path to the INPUT IMAGE directory: ").strip())
    weights_dir = Path(input("Enter path to the WEIGHTS & BIASES directory: ").strip())
    output_dir = Path(input("Enter path for the main OUTPUT directory: ").strip())
    class_index_path = Path(input("Enter path to the ImageNet class index JSON file: ").strip())

    # --- Load Class Names ---
    try:
        with class_index_path.open("r") as f:
            class_names = {key: value[1] for key, value in json.load(f).items()}
        print("✅ Class names loaded successfully.")
    except Exception as e:
        print(f"❌ FATAL ERROR loading or parsing class index JSON: {e}", file=sys.stderr)
        sys.exit(1)

    # --- Load Weights ---
    weights, biases = load_weights(weights_dir)

    # --- Process Each Image ---
    image_files = list(image_dir.glob('*.jpg')) + list(image_dir.glob('*.png')) + list(image_dir.glob('*.jpeg'))
    if not image_files:
        print(f"❌ FATAL ERROR: No images found in '{image_dir}'", file=sys.stderr)
        sys.exit(1)
    
    print(f"\n✅ Found {len(image_files)} images to process.")

    for image_path in image_files:
        print(f"\n\n{'='*25} Processing Image: {image_path.name} {'='*25}")
        image_output_dir = output_dir / image_path.stem
        step = 0
        
        try:
            # --- STAGE 0: Input Processing ---
            img = Image.open(image_path).convert('RGB').resize((227, 227), Image.Resampling.BILINEAR)
            ifmap = np.vectorize(float_to_q313_int16)(np.array(img).astype(np.float32) / 255.0)
            save_stage_outputs(f"{step:02d}_input", ifmap, image_output_dir); step += 1
            
            # --- LAYER 1: CONV1 -> RELU -> MAX1 ---
            conv1 = conv2d_q313(ifmap, weights['conv1'], biases['conv1'], stride=4)
            save_stage_outputs(f"{step:02d}_conv1", conv1, image_output_dir); step += 1
            relu1 = apply_relu(conv1)
            save_stage_outputs(f"{step:02d}_relu1", relu1, image_output_dir); step += 1
            max1 = max_pooling_3d(relu1, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool1", max1, image_output_dir); step += 1
            
            # --- LAYER 2: PAD -> CONV2 -> RELU -> MAX2 ---
            pad2 = apply_padding(max1, pad=2)
            save_stage_outputs(f"{step:02d}_padding2", pad2, image_output_dir); step += 1
            conv2 = conv2d_q313(pad2, weights['conv2'], biases['conv2'], stride=1)
            save_stage_outputs(f"{step:02d}_conv2", conv2, image_output_dir); step += 1
            relu2 = apply_relu(conv2)
            save_stage_outputs(f"{step:02d}_relu2", relu2, image_output_dir); step += 1
            max2 = max_pooling_3d(relu2, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool2", max2, image_output_dir); step += 1
            
            # --- LAYER 3: PAD -> CONV3 -> RELU ---
            pad3 = apply_padding(max2, pad=1)
            save_stage_outputs(f"{step:02d}_padding3", pad3, image_output_dir); step += 1
            conv3 = conv2d_q313(pad3, weights['conv3'], biases['conv3'], stride=1)
            save_stage_outputs(f"{step:02d}_conv3", conv3, image_output_dir); step += 1
            relu3 = apply_relu(conv3)
            save_stage_outputs(f"{step:02d}_relu3", relu3, image_output_dir); step += 1
            
            # --- LAYER 4: PAD -> CONV4 -> RELU ---
            pad4 = apply_padding(relu3, pad=1)
            save_stage_outputs(f"{step:02d}_padding4", pad4, image_output_dir); step += 1
            conv4 = conv2d_q313(pad4, weights['conv4'], biases['conv4'], stride=1)
            save_stage_outputs(f"{step:02d}_conv4", conv4, image_output_dir); step += 1
            relu4 = apply_relu(conv4)
            save_stage_outputs(f"{step:02d}_relu4", relu4, image_output_dir); step += 1
            
            # --- LAYER 5: PAD -> CONV5 -> RELU -> MAX3 ---
            pad5 = apply_padding(relu4, pad=1)
            save_stage_outputs(f"{step:02d}_padding5", pad5, image_output_dir); step += 1
            conv5 = conv2d_q313(pad5, weights['conv5'], biases['conv5'], stride=1)
            save_stage_outputs(f"{step:02d}_conv5", conv5, image_output_dir); step += 1
            relu5 = apply_relu(conv5)
            save_stage_outputs(f"{step:02d}_relu5", relu5, image_output_dir); step += 1
            max3 = max_pooling_3d(relu5, pool_size=3, stride=2)
            save_stage_outputs(f"{step:02d}_maxpool3", max3, image_output_dir); step += 1
            
            # --- FLATTEN & FC Layers ---
            flat = max3.flatten()
            fc1 = fully_connected_layer(flat, weights['fc1'], biases['fc1'])
            save_fc_output(f"{step:02d}_fc1", fc1, image_output_dir); step += 1
            relu_fc1 = apply_relu(fc1)
            save_fc_output(f"{step:02d}_relu_fc1", relu_fc1, image_output_dir); step += 1
            
            fc2 = fully_connected_layer(relu_fc1, weights['fc2'], biases['fc2'])
            save_fc_output(f"{step:02d}_fc2", fc2, image_output_dir); step += 1
            relu_fc2 = apply_relu(fc2)
            save_fc_output(f"{step:02d}_relu_fc2", relu_fc2, image_output_dir); step += 1
            
            fc3 = fully_connected_layer(relu_fc2, weights['fc3'], biases['fc3'])
            save_fc_output(f"{step:02d}_fc3_output", fc3, image_output_dir); step += 1
            
            # --- Final Prediction Output ---
            top5_indices = np.argsort(fc3)[::-1][:5]
            print("\n" + "="*20 + f" TOP 5 PREDICTIONS FOR: {image_path.name} " + "="*20)
            for i, idx in enumerate(top5_indices):
                class_name = class_names.get(str(idx), "Unknown Class")
                marker = "🏆" if i == 0 else f"  {i+1}."
                print(f"{marker} Class: {class_name.replace('_', ' ').title()} (Index: {idx}, Score: {fc3[idx]})")
            print("="*70)

        except Exception as e:
            print(f"\n❌ An error occurred while processing {image_path.name}: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            print("  Skipping to the next image.", file=sys.stderr)

    print("\n\n✨ AlexNet batch processing finished successfully! ✨")

if __name__ == "__main__":
    main()
