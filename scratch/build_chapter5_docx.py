import re
import docx
from docx.shared import Pt, Emu
from docx.enum.text import WD_ALIGN_PARAGRAPH

SRC = "../chapter_5.txt"
OUT = "../chapter_5.docx"

with open(SRC, "r", encoding="utf-8") as f:
    raw_lines = [l.rstrip("\n") for l in f.readlines()]

doc = docx.Document()

# ── Page setup: match the project's existing thesis docx (A4, same margins) ──
sec = doc.sections[0]
sec.page_width = Emu(7560945)
sec.page_height = Emu(10693400)
sec.left_margin = Emu(1170305)
sec.right_margin = Emu(1170305)
sec.top_margin = Emu(1800225)
sec.bottom_margin = Emu(1800225)

# ── Base style ──
normal = doc.styles["Normal"]
normal.font.name = "Times New Roman"
normal.font.size = Pt(12)
normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
normal.paragraph_format.space_after = Pt(8)
normal.paragraph_format.line_spacing = 1.5

h1 = doc.styles["Heading 1"]
h1.font.name = "Times New Roman"
h1.font.size = Pt(16)
h1.font.bold = True
h1.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
h1.paragraph_format.space_after = Pt(12)

h2 = doc.styles["Heading 2"]
h2.font.name = "Times New Roman"
h2.font.size = Pt(14)
h2.font.bold = True
h2.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
h2.paragraph_format.space_before = Pt(18)
h2.paragraph_format.space_after = Pt(8)

h3 = doc.styles["Heading 3"]
h3.font.name = "Times New Roman"
h3.font.size = Pt(13)
h3.font.bold = True
h3.paragraph_format.space_before = Pt(12)
h3.paragraph_format.space_after = Pt(6)

h4 = doc.styles["Heading 4"]
h4.font.name = "Times New Roman"
h4.font.size = Pt(12)
h4.font.bold = True
h4.font.italic = True
h4.paragraph_format.space_before = Pt(10)
h4.paragraph_format.space_after = Pt(6)

HEAD4_RE = re.compile(r"^(\d+\.\d+\.\d+\.\d+)\s+(.+)$")
HEAD3_RE = re.compile(r"^(\d+\.\d+\.\d+)\s+(.+)$")
HEAD2_RE = re.compile(r"^(\d+\.\d+)\s+(.+)$")
SEP_RE = re.compile(r"^[\s\-|]+$")
FIGTAB_RE = re.compile(r"^(Figure|Table)\s+5\.\d+")

def add_caption(text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(14)
    r = p.add_run(text)
    r.font.name = "Times New Roman"
    r.font.size = Pt(12)
    r.font.bold = True

def add_body(text):
    p = doc.add_paragraph()
    if text.startswith("[Note:"):
        r = p.add_run(text)
        r.italic = True
    elif text.startswith("Outstanding Verification Items."):
        lead = "Outstanding Verification Items."
        r1 = p.add_run(lead)
        r1.bold = True
        p.add_run(" " + text[len(lead):].lstrip())
    else:
        p.add_run(text)

def add_table(header_cells, data_rows):
    table = doc.add_table(rows=1, cols=len(header_cells))
    table.style = "Table Grid"
    table.autofit = True
    hdr = table.rows[0].cells
    for i, htext in enumerate(header_cells):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        r = p.add_run(htext)
        r.bold = True
        r.font.size = Pt(10)
    for row in data_rows:
        cells = table.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            r = p.add_run(val)
            r.font.size = Pt(10)
    spacer = doc.add_paragraph()
    spacer.paragraph_format.space_after = Pt(14)

# ── Strip leading/trailing blank lines, group into logical lines ──
lines = raw_lines
i = 0
n = len(lines)

# First two non-blank lines: "CHAPTER 5" and "IMPLEMENTATION AND TESTING"
while i < n and not lines[i].strip():
    i += 1
chapter_label = lines[i].strip()
i += 1
while i < n and not lines[i].strip():
    i += 1
chapter_title = lines[i].strip()
i += 1

p = doc.add_paragraph(style="Heading 1")
r1 = p.add_run(chapter_label)
r1.add_break()
r1.add_break()
r2 = p.add_run(chapter_title)

while i < n:
    line = lines[i]
    stripped = line.strip()

    if not stripped:
        i += 1
        continue

    m4 = HEAD4_RE.match(stripped)
    m3 = HEAD3_RE.match(stripped) if not m4 else None
    m2 = HEAD2_RE.match(stripped) if not m4 and not m3 else None

    if m4:
        doc.add_paragraph(stripped, style="Heading 4")
        i += 1
        continue
    if m3:
        doc.add_paragraph(stripped, style="Heading 3")
        i += 1
        continue
    if m2:
        doc.add_paragraph(stripped, style="Heading 2")
        i += 1
        continue

    if FIGTAB_RE.match(stripped):
        add_caption(stripped)
        i += 1
        continue

    # Possible table: this line is a header row if the NEXT non-empty line is a separator
    if i + 1 < n and "|" in stripped and SEP_RE.match(lines[i + 1].strip() or " "):
        header_cells = [c.strip() for c in stripped.split("|")]
        i += 2  # skip header + separator
        data_rows = []
        while i < n and lines[i].strip() and "|" in lines[i]:
            data_rows.append([c.strip() for c in lines[i].split("|")])
            i += 1
        add_table(header_cells, data_rows)
        continue

    add_body(stripped)
    i += 1

doc.save(OUT)
print("Saved", OUT)
print("Paragraphs:", len(doc.paragraphs), "Tables:", len(doc.tables))
