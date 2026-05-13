import os
import numpy as np
from PIL import Image

# --- Configuration Constants ---
# Image settings
IMAGE_WIDTH = 227
IMAGE_HEIGHT = 227
CHANNELS = 3

# Segmentation settings
ROWS_PER_SEGMENT = 35
OVERLAP = 7

# --- Stage 1: Image Resizing ---
def resize_image(input_path, output_path):
    """
    Resizes an image to 227x227 and saves it.
    Returns the resized PIL Image object.
    """
    print(f"[*] Resizing image: {os.path.basename(input_path)}")
    img = Image.open(input_path).convert('RGB')
    img_resized = img.resize((IMAGE_WIDTH, IMAGE_HEIGHT), Image.BILINEAR)
    img_resized.save(output_path, format='JPEG')
    print(f"  ✅ Saved resized image to: {output_path}")
    return img_resized

# --- Stage 2: Q3.13 Fixed-Point Conversion ---
def float_to_q313_bin(val):
    """Converts a float to a 16-bit Q3.13 binary string."""
    max_val = 7.9998779296875  # (2^3 - 2^-13)
    min_val = -8.0             # -2^3
    val = min(max(val, min_val), max_val)
    scaled = int(round(val * (2 ** 13)))
    if scaled < 0:
        scaled = (1 << 16) + scaled
    return format(scaled, '016b')

def convert_image_to_q313_lines(img_obj):
    """
    Converts a PIL image object to a list of Q3.13 binary strings.
    """
    print("[*] Converting resized image to Q3.13 fixed-point format...")
    np_img = np.array(img_obj).astype(np.float32) / 255.0
    np_img = np.transpose(np_img, (2, 0, 1))  # Reorder to (C, H, W)
    
    lines = []
    channels, height, width = np_img.shape
    for c in range(channels):
        for h in range(height):
            for w in range(width):
                binary_val = float_to_q313_bin(np_img[c, h, w])
                lines.append(binary_val)
    return lines

# --- Stage 3: Segmentation ---
def segment_q313_data(q313_lines):
    """
    Splits the full list of Q3.13 lines into overlapping segments.
    Returns a dictionary where keys are segment filenames and values are the line data.
    """
    print("[*] Segmenting the Q3.13 data...")
    pixels_per_channel = IMAGE_WIDTH * IMAGE_HEIGHT
    ch1 = q313_lines[0 : pixels_per_channel]
    ch2 = q313_lines[pixels_per_channel : 2 * pixels_per_channel]
    ch3 = q313_lines[2 * pixels_per_channel : 3 * pixels_per_channel]
    channels = [ch1, ch2, ch3]

    start_rows = [0]
    while start_rows[-1] + ROWS_PER_SEGMENT < IMAGE_HEIGHT:
        next_start = start_rows[-1] + ROWS_PER_SEGMENT - OVERLAP
        start_rows.append(next_start)

    segments = {}
    for idx, start_row in enumerate(start_rows):
        segment_data = []
        for ch_lines in channels:
            for i in range(start_row, start_row + ROWS_PER_SEGMENT):
                if i >= IMAGE_HEIGHT:
                    segment_data.extend(['0' * 16] * IMAGE_WIDTH)
                else:
                    start_idx = i * IMAGE_WIDTH
                    end_idx = start_idx + IMAGE_WIDTH
                    segment_data.extend(ch_lines[start_idx:end_idx])
        
        segment_name = f"segment_{idx+1}_16bit.txt"
        segments[segment_name] = segment_data
        
    print(f"  ✅ Generated data for {len(segments)} segments.")
    return segments

# --- Stage 4: Merging to 64-bit ---
def merge_16bit_to_64bit(lines_16bit):
    """
    Merges a list of 16-bit binary strings (4 at a time) into 64-bit strings.
    """
    if len(lines_16bit) % 4 != 0:
        padding_needed = 4 - (len(lines_16bit) % 4)
        lines_16bit.extend(['0' * 16] * padding_needed)

    output_lines_64bit = []
    for i in range(0, len(lines_16bit), 4):
        merged = ''.join(lines_16bit[i:i+4][::-1])
        output_lines_64bit.append(merged)
        
    return output_lines_64bit

# --- Core Processing Function for a Single Image ---
def process_single_image(image_path, base_output_dir):
    """Runs the full processing pipeline for one image."""
    try:
        image_base_name = os.path.splitext(os.path.basename(image_path))[0]
        
        # Create dedicated subdirectories for this image's output
        intermediate_dir = os.path.join(base_output_dir, "intermediate_files")
        final_dir = os.path.join(base_output_dir, "final_64bit_segments")
        os.makedirs(intermediate_dir, exist_ok=True)
        os.makedirs(final_dir, exist_ok=True)

        # STAGE 1: RESIZE
        resized_img_path = os.path.join(intermediate_dir, f"{image_base_name}_227x227.jpg")
        resized_img_obj = resize_image(image_path, resized_img_path)

        # STAGE 2: CONVERT TO Q3.13
        q313_lines = convert_image_to_q313_lines(resized_img_obj)
        q313_full_path = os.path.join(intermediate_dir, f"{image_base_name}_q313_full.txt")
        with open(q313_full_path, 'w') as f:
            f.write('\n'.join(q313_lines))
        print(f"  ✅ Saved full Q3.13 data to: {q313_full_path}")

        # STAGE 3: SEGMENT DATA
        segments_16bit = segment_q313_data(q313_lines)

        # STAGE 4: MERGE SEGMENTS & SAVE
        print("[*] Merging segments to 64-bit words and saving final files...")
        for name, data_16bit in segments_16bit.items():
            data_64bit = merge_16bit_to_64bit(data_16bit)
            final_filename = name.replace("_16bit.txt", "_64bit_merged.txt")
            output_path = os.path.join(final_dir, final_filename)
            with open(output_path, 'w') as f:
                f.write('\n'.join(data_64bit))
            print(f"  ✅ Saved final merged file: {output_path}")

    except Exception as e:
        print(f"❌ An unexpected error occurred while processing {os.path.basename(image_path)}: {e}")


# --- Main Orchestrator ---
def main():
    """Main function to find and process all images in a directory."""
    print("--- Image Batch to 64-bit Segmented Words Pipeline ---")
    
    # 1. Get User Input
    input_dir_path = input("Enter the path to the input DIRECTORY containing images: ").strip()
    if not os.path.isdir(input_dir_path):
        print("❌ Error: Input directory not found.")
        return
        
    main_output_dir_name = input("Enter a name for the main output directory: ").strip()
    if not main_output_dir_name:
        print("❌ Error: Output directory name cannot be empty.")
        return

    # 2. Find all images in the directory
    supported_extensions = ['.jpg', '.jpeg', '.png', '.bmp']
    image_files = [f for f in os.listdir(input_dir_path) if os.path.splitext(f)[1].lower() in supported_extensions]

    if not image_files:
        print("❌ No supported image files found in the specified directory.")
        return

    print(f"\nFound {len(image_files)} images to process.")
    
    # 3. Process each image file
    for image_name in image_files:
        image_path = os.path.join(input_dir_path, image_name)
        image_base_name = os.path.splitext(image_name)[0]
        
        # Create a dedicated output folder for each image
        image_specific_output_dir = os.path.join(os.getcwd(), main_output_dir_name, f"{image_base_name}_output")
        
        print(f"\n--- Processing: {image_name} ---")
        print(f"Results will be saved in: {image_specific_output_dir}")
        
        process_single_image(image_path, image_specific_output_dir)

    print("\n🎉 Batch processing finished successfully!")


if __name__ == '__main__':
    main()