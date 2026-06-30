import shutil
import os

src = r"C:\Users\navve\projects\cryptransfer\scratch\erd_plantuml_layout.png"
dst = r"C:\Users\navve\.gemini\antigravity-ide\brain\b5a84fbd-e2a2-4d1b-80b4-3e619e947006\erd_plantuml.png"

if os.path.exists(src):
    shutil.copy(src, dst)
    print(f"Copied {src} to {dst}")
else:
    print(f"Source file {src} not found!")
