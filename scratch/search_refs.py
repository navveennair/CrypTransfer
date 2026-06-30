import os

workspace = r"C:\Users\navve\projects\cryptransfer"
queries = ["erd_single_page", "image1.png", "image2.png", "CrypTransfer_Database_Design_ERD_Corrected_v3"]

for root, dirs, files in os.walk(workspace):
    # Skip python environment dirs and git
    if any(d in root for d in [".git", ".dart_tool", "build", "node_modules"]):
        continue
    for file in files:
        if file.endswith((".py", ".md", ".json", ".txt", ".sh", ".ps1", ".bat")):
            filepath = os.path.join(root, file)
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    for q in queries:
                        if q in content:
                            print(f"Found '{q}' in {filepath}")
            except Exception as e:
                pass
