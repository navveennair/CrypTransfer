import zipfile
import os
import shutil

docx_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"
artifact_dir = r"C:\Users\navve\.gemini\antigravity-ide\brain\b5a84fbd-e2a2-4d1b-80b4-3e619e947006"

os.makedirs(artifact_dir, exist_ok=True)

with zipfile.ZipFile(docx_path) as docx:
    for name in docx.namelist():
        if 'media' in name:
            filename = os.path.basename(name)
            target_path = os.path.join(artifact_dir, filename)
            with docx.open(name) as src, open(target_path, 'wb') as dst:
                shutil.copyfileobj(src, dst)
            print(f"Extracted {name} to {target_path}")

# Also check graphify-out/erd_single_page.png and copy it if it exists
erd_graphify = r"C:\Users\navve\projects\cryptransfer\graphify-out\erd_single_page.png"
if os.path.exists(erd_graphify):
    target_path = os.path.join(artifact_dir, "erd_single_page.png")
    shutil.copy(erd_graphify, target_path)
    print(f"Copied erd_single_page.png to {target_path}")
