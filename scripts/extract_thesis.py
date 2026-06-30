import docx
import os

def extract_thesis_text(docx_path):
    if not os.path.exists(docx_path):
        print(f"Error: File not found at {docx_path}")
        return

    try:
        doc = docx.Document(docx_path)
        full_text = []
        for para in doc.paragraphs:
            full_text.append(para.text)
        
        # Save to a temporary text file in the workspace for easier reading
        output_path = "thesis_full_text.txt"
        with open(output_path, "w", encoding="utf-8") as f:
            f.write("\n".join(full_text))
        
        print(f"Success! Extracted text saved to {output_path}")
    except Exception as e:
        print(f"Error extracting text: {e}")

if __name__ == "__main__":
    # Path provided by the user
    path = r"C:\Users\navve\Downloads\Corrected PSM Thesis - NavveenNairManoharan.docx"
    extract_thesis_text(path)
