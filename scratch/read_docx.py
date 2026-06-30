import zipfile
import xml.etree.ElementTree as ET
import os

docx_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"

if not os.path.exists(docx_path):
    print(f"File not found: {docx_path}")
    exit(1)

def extract_text(docx_file):
    try:
        with zipfile.ZipFile(docx_file) as docx:
            xml_content = docx.read('word/document.xml')
            root = ET.fromstring(xml_content)
            
            # Namespace map
            ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            
            # Find all paragraphs
            text_lines = []
            for p in root.findall('.//w:p', ns):
                p_text = []
                for r in p.findall('.//w:r', ns):
                    t = r.find('.//w:t', ns)
                    if t is not None and t.text:
                        p_text.append(t.text)
                if p_text:
                    text_lines.append("".join(p_text))
            
            # Also check if there are tables
            print(f"Extracted {len(text_lines)} paragraph lines.")
            with open("scratch/extracted_docx_text.txt", "w", encoding="utf-8") as f:
                for line in text_lines:
                    f.write(line + "\n")
            print("Successfully wrote extracted paragraphs to scratch/extracted_docx_text.txt")
            
            # Check for relationships or other xml files (like diagrams, draw.io, mermaid, etc.)
            for name in docx.namelist():
                if 'embeddings' in name or 'media' in name:
                    print(f"Found media/embedding: {name}")
                    
    except Exception as e:
        print(f"Error: {e}")

extract_text(docx_path)
