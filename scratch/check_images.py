from PIL import Image
import os

artifact_dir = r"C:\Users\navve\.gemini\antigravity-ide\brain\b5a84fbd-e2a2-4d1b-80b4-3e619e947006"

for filename in ["image1.png", "image2.png", "erd_single_page.png"]:
    path = os.path.join(artifact_dir, filename)
    if os.path.exists(path):
        with Image.open(path) as img:
            print(f"{filename}: size={img.size}, format={img.format}, mode={img.mode}")
    else:
        print(f"{filename} does not exist in artifact dir")
