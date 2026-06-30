from PIL import Image
import os

path = r"C:\Users\navve\projects\cryptransfer\scratch\erd_plantuml_layout.png"
if os.path.exists(path):
    with Image.open(path) as img:
        print(f"PlantUML layout image: size={img.size}, format={img.format}, aspect_ratio={img.width/img.height:.2f}")
else:
    print("Image not found")
