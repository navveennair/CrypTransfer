import zipfile
import shutil
import os

docx_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"
backup_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3_backup.docx"
new_image_path = r"C:\Users\navve\projects\cryptransfer\scratch\erd_mermaid.png"
temp_dir = r"C:\Users\navve\projects\cryptransfer\scratch\temp_docx"

# Create a backup first
shutil.copy(docx_path, backup_path)
print(f"Created backup of DOCX at {backup_path}")

# Extract zip contents to a temporary directory
if os.path.exists(temp_dir):
    shutil.rmtree(temp_dir)
os.makedirs(temp_dir)

with zipfile.ZipFile(docx_path, 'r') as zip_ref:
    zip_ref.extractall(temp_dir)
print(f"Extracted DOCX XML contents to {temp_dir}")

# Replace the target image
target_image_in_docx = os.path.join(temp_dir, 'word', 'media', 'image2.png')
if os.path.exists(target_image_in_docx):
    shutil.copy(new_image_path, target_image_in_docx)
    print(f"Replaced image at {target_image_in_docx}")
else:
    print(f"Error: Target image {target_image_in_docx} not found in DOCX structure!")
    exit(1)

# Re-zip the contents
new_docx_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"
# Delete existing new_docx if it's there
if os.path.exists(new_docx_path):
    os.remove(new_docx_path)

# Zip files back
with zipfile.ZipFile(new_docx_path, 'w', zipfile.ZIP_DEFLATED) as zip_out:
    for root, dirs, files in os.walk(temp_dir):
        for file in files:
            full_path = os.path.join(root, file)
            # Store relative path
            rel_path = os.path.relpath(full_path, temp_dir)
            zip_out.write(full_path, rel_path)

print(f"Success! Repacked new docx at {new_docx_path}")

# Clean up temp files
shutil.rmtree(temp_dir)
print("Temporary files cleaned up.")
