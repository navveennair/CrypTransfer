import zipfile
import xml.etree.ElementTree as ET

docx_path = r"C:\Users\navve\projects\cryptransfer\CrypTransfer_Database_Design_ERD_Corrected_v3.docx"

with zipfile.ZipFile(docx_path) as docx:
    # Read document.xml.rels to see what IDs map to what images
    rels_xml = docx.read('word/_rels/document.xml.rels')
    root_rels = ET.fromstring(rels_xml)
    ns_rels = {'r': 'http://schemas.openxmlformats.org/package/2006/relationships'}
    
    rId_to_target = {}
    for rel in root_rels.findall('.//r:Relationship', ns_rels):
        rid = rel.attrib.get('Id')
        target = rel.attrib.get('Target')
        rId_to_target[rid] = target
        print(f"Rel: Id={rid}, Target={target}")
        
    # Read document.xml
    doc_xml = docx.read('word/document.xml')
    root_doc = ET.fromstring(doc_xml)
    ns_doc = {
        'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
        'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture'
    }
    
    # Find all blip elements which reference images
    for i, blip in enumerate(root_doc.findall('.//a:blip', ns_doc)):
        embed_rid = blip.attrib.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}embed')
        target = rId_to_target.get(embed_rid, "unknown")
        print(f"Blip {i}: embed={embed_rid} -> Target={target}")
