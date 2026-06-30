from PIL import Image
import os

artifact_dir = r"C:\Users\navve\.gemini\antigravity-ide\brain\b5a84fbd-e2a2-4d1b-80b4-3e619e947006"
path = os.path.join(artifact_dir, "image2.png")

if os.path.exists(path):
    with Image.open(path) as img:
        # Check colors of a few pixels at the corners
        pixels = [
            img.getpixel((0, 0)),
            img.getpixel((img.width - 1, 0)),
            img.getpixel((0, img.height - 1)),
            img.getpixel((img.width - 1, img.height - 1)),
            img.getpixel((img.width // 2, img.height // 2))
        ]
        print(f"Corner and center pixels: {pixels}")
else:
    print("image2.png not found")
