import numpy as np
from PIL import Image
from pathlib import Path
import sys

# ------------------------- Helper Functions -------------------------

def float_to_q313_int16(val: float) -> np.int16:
    """Converts a float to a Q3.13 16-bit signed integer."""
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

# ------------------------- Core Logic: Modes -------------------------

def run_image_to_q313():
    """Mode 1: Converts an image file to a Q3.13 text file."""
    print("\n--- Mode: Image to Q3.13 .txt ---")
    input_path = Path(input("Enter the path to the input image: ").strip())

    if not input_path.is_file():
        print(f"❌ Error: File not found at '{input_path}'")
        return

    # 1. Process image: Open, resize, normalize
    img = Image.open(input_path).convert('RGB').resize((227, 227), Image.BILINEAR)
    np_img_float = np.array(img).astype(np.float32) / 255.0

    # 2. Convert float values to Q3.13 fixed-point format
    q313_vectorized = np.vectorize(float_to_q313_int16)
    np_img_q313 = q313_vectorized(np_img_float)
    
    # 3. Transpose from (H, W, C) to (C, H, W) for standard tensor layout
    tensor_chw = np.transpose(np_img_q313, (2, 0, 1))

    # 4. Save to text file
    output_path = input_path.with_suffix('.txt')
    try:
        with output_path.open("w") as f:
            # Flatten the tensor and write each value as a binary string
            for val in tensor_chw.flatten():
                f.write(int16_to_bin16(val) + "\n")
        print(f"✅ Q3.13 data saved successfully to: {output_path}")
    except IOError as e:
        print(f"❌ Error saving file: {e}")


def run_q313_to_image():
    """Mode 2: Converts a Q3.13 text file back to an image."""
    print("\n--- Mode: Q3.13 .txt to Image ---")
    input_path = Path(input("Enter the path to the input Q3.13 .txt file: ").strip())

    if not input_path.is_file():
        print(f"❌ Error: File not found at '{input_path}'")
        return

    # 1. Get image dimensions from user
    print("\nNOTE: You must provide the original dimensions of the image.")
    try:
        H = int(input("Original Image Height (e.g., 227): "))
        W = int(input("Original Image Width (e.g., 227): "))
        C = int(input("Original Image Channels (e.g., 3 for RGB): "))
    except ValueError:
        print("❌ Error: Please enter valid integers.")
        return

    # 2. Load and convert data from the text file
    try:
        lines = input_path.read_text().splitlines()
        int16_data = np.array([bin16_to_int16(line) for line in lines], dtype=np.int16)
        float_data = np.array([q313_int16_to_float(val) for val in int16_data], dtype=np.float32)

        # 3. Reshape and denormalize
        image_tensor_chw = float_data.reshape(C, H, W)
        image_tensor_hwc = image_tensor_chw.transpose(1, 2, 0)
        pixel_data = np.clip(image_tensor_hwc * 255.0, 0, 255).astype(np.uint8)

        # 4. Create and save the image
        img = Image.fromarray(pixel_data, 'RGB')
        output_path = input_path.with_name(f"{input_path.stem}_restored.jpg")
        img.save(output_path, 'JPEG')
        
        print(f"\n✅ Image reconstructed successfully and saved to: {output_path}")

    except Exception as e:
        print(f"❌ An error occurred. Check if dimensions are correct. Details: {e}")

# ------------------------- Main Menu Router -------------------------

def main():
    """Acts as a menu to route the user to the correct mode."""
    print("=== Universal Q3.13 Image/Data Converter ===")
    while True:
        print("\nPlease select a mode:")
        print("  1: Convert Image to Q3.13 .txt file")
        print("  2: Convert Q3.13 .txt file to Image")
        print("  Q: Quit")
        
        choice = input("Enter your choice (1, 2, or Q): ").strip().upper()

        if choice == '1':
            run_image_to_q313()
            break
        elif choice == '2':
            run_q313_to_image()
            break
        elif choice == 'Q':
            print("Exiting.")
            break
        else:
            print("❌ Invalid choice. Please try again.")

if __name__ == "__main__":
    main()