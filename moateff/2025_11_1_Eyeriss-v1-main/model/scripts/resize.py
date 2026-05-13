from PIL import Image
import os

def resize_image_to_alexnet(input_path, output_path=None):
    # Open image and convert to RGB
    img = Image.open(input_path).convert('RGB')

    # Resize to 227x227 (AlexNet input size)
    img_resized = img.resize((227, 227), Image.BILINEAR)

    # Auto-generate output filename if not provided
    if output_path is None:
        base, ext = os.path.splitext(input_path)
        output_path = f"{base}_227x227.jpg"

    img_resized.save(output_path, format='JPEG')
    print(f"✅ Saved resized image to: {output_path}")

def main():
    print("=== Resize Image for AlexNet ===")
    input_path = input("Enter the path to the input image: ").strip()

    if not os.path.exists(input_path):
        print("❌ File not found.")
        return

    resize_image_to_alexnet(input_path)

if __name__ == "__main__":
    main()
