import zipfile, shutil, os

src  = r"C:\Users\navve\projects\cryptransfer\scratch\erd_thesis_original.png"
docx_in  = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"
docx_out = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v4.docx"
tmp  = r"C:\Users\navve\projects\cryptransfer\scratch\tmp_thesis2"

if os.path.exists(tmp): shutil.rmtree(tmp)
os.makedirs(tmp)
with zipfile.ZipFile(docx_in, 'r') as z: z.extractall(tmp)

tgt = os.path.join(tmp, 'word', 'media', 'image2.png')
shutil.copy(src, tgt)
print("Image replaced in extracted DOCX.")

if os.path.exists(docx_out): os.remove(docx_out)
with zipfile.ZipFile(docx_out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(tmp):
        for f in files:
            fp = os.path.join(root, f)
            z.write(fp, os.path.relpath(fp, tmp))

shutil.rmtree(tmp)
print(f"New DOCX saved: {docx_out}")
