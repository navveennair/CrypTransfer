import docx
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

doc = docx.Document(r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx")

print(f"Total paragraphs: {len(doc.paragraphs)}")
print(f"Total tables: {len(doc.tables)}")
print(f"Total sections: {len(doc.sections)}")

for i, p in enumerate(doc.paragraphs):
    if "Figure" in p.text or "figure" in p.text.lower():
        print(f"Paragraph {i}: {p.text}")
    # Check if this paragraph contains an image
    p_xml = p._element
    if 'w:drawing' in p_xml.xml:
        print(f"Paragraph {i} contains a drawing. Text: '{p.text}'")

for i, table in enumerate(doc.tables):
    print(f"Table {i}: {len(table.rows)} rows x {len(table.columns)} columns")
    # Print the first row's cells to identify the table
    first_row = [cell.text.strip().replace("\n", " ")[:30] for cell in table.rows[0].cells]
    print(f"  First row: {first_row}")
