"""
Extract AlexNet Conv1-5 weights from torchvision pretrained model → Q3.13 format.
Uses torchvision's standard AlexNet (trained on ImageNet).
Output format matches: model/alexnet/alexnet.py load_weights() expectations.

Usage: python extract_alexnet_weights.py
Output: weights_q313/conv{1-5}_filter_16.txt, weights_q313/conv{1-5}_bias_16.txt
"""

import numpy as np
import torch
import torchvision.models as models
from pathlib import Path

# ============================================================================
# Q3.13 Fixed-Point Parameters
# ============================================================================
FL = 13
SCALE = float(1 << FL)  # 8192
Q_MAX = float((1 << 15) - 1) / SCALE   # 3.9998779296875
Q_MIN = float(-(1 << 15)) / SCALE       # -4.0


def float_to_q313(val):
    """Convert float to Q3.13 int16 with symmetric saturation."""
    clamped = max(Q_MIN, min(Q_MAX, val))
    return np.int16(round(clamped * SCALE))


def int16_to_bin16(x):
    """Convert int16 to 16-character binary string."""
    return format(np.uint16(x), "016b")


def save_tensor_q313(tensor, out_path):
    """Flatten tensor, quantize, save as 16-bit binary txt (one per line)."""
    arr = tensor.detach().cpu().flatten().numpy()
    q_vals = np.array([float_to_q313(v) for v in arr], dtype=np.int16)
    with open(out_path, "w") as f:
        for v in q_vals:
            f.write(int16_to_bin16(v) + "\n")

    # Statistics
    f_orig = arr
    f_quant = q_vals.astype(np.float64) / SCALE
    max_err = np.max(np.abs(f_orig - np.clip(f_quant, Q_MIN, Q_MAX)))
    print(f"  Values: {len(q_vals):,},  Range: [{q_vals.min()}, {q_vals.max()}]")
    print(f"  Max quantization error: {max_err:.6f}")
    return q_vals


# ============================================================================
# Load Pretrained AlexNet
# ============================================================================
print("Loading pretrained AlexNet from torchvision...")
model = models.alexnet(weights=models.AlexNet_Weights.IMAGENET1K_V1)
model.eval()
state = model.state_dict()

print("\nLayer dimensions:")
for k, v in state.items():
    if "weight" in k or "bias" in k:
        print(f"  {k}: {list(v.shape)}")

# ============================================================================
# Extract Conv1-5 Weights and Biases
# ============================================================================
out_dir = Path("weights_q313")
out_dir.mkdir(exist_ok=True)

# Feature layer index mapping (torchvision AlexNet)
# features.0 = Conv1, features.3 = Conv2, features.6 = Conv3
# features.8 = Conv4, features.10 = Conv5
conv_map = [
    ("features.0",  "conv1", 3,   64,  11),   # Conv1: 3→64, 11×11
    ("features.3",  "conv2", 64,  192, 5),    # Conv2: 64→192, 5×5
    ("features.6",  "conv3", 192, 384, 3),    # Conv3: 192→384, 3×3
    ("features.8",  "conv4", 384, 256, 3),    # Conv4: 384→256, 3×3
    ("features.10", "conv5", 256, 256, 3),    # Conv5: 256→256, 3×3
]

for feat_key, name, C_in, M_out, K in conv_map:
    w_key = f"{feat_key}.weight"
    b_key = f"{feat_key}.bias"

    print(f"\n{'='*60}")
    print(f"{name}: C_in={C_in}, M_out={M_out}, Kernel={K}x{K}")
    print(f"  PyTorch weight shape: {list(state[w_key].shape)}")

    # Save filter weights
    fname_w = out_dir / f"{name}_filter_16.txt"
    print(f"  Filter → {fname_w}")
    save_tensor_q313(state[w_key], fname_w)

    # Save bias
    fname_b = out_dir / f"{name}_bias_16.txt"
    print(f"  Bias   → {fname_b}")
    save_tensor_q313(state[b_key], fname_b)

print(f"\nDone. All files saved to: {out_dir.absolute()}")
