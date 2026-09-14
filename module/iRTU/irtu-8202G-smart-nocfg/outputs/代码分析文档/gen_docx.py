# -*- coding: utf-8 -*-
"""Markdown → Word (.docx) 转换器（面向本代码分析文档）。
支持 ATX 标题、表格、代码块、图片、加粗/斜体/行内代码、列表。
"""
import os
import re
from docx import Document
from docx.shared import Inches, Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.style import WD_STYLE_TYPE
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

MD_PATH = os.path.join(os.path.dirname(__file__), "Air8202G固件代码分析文档.md")
OUT_PATH = os.path.join(os.path.dirname(__file__), "Air8202G固件代码分析文档.docx")
IMAGES_DIR = os.path.join(os.path.dirname(__file__), "images")

NAVY = RGBColor(0x0F, 0x35, 0x50)
AMBER = RGBColor(0xD9, 0xA4, 0x41)
GREY = RGBColor(0x5A, 0x67, 0x72)
BG_CODE = RGBColor(0xF4, 0xF8, 0xFB)


def set_chinese_font(run, name="Microsoft YaHei", size=10.5, bold=False, color=NAVY):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color


def add_shading(cell_or_paragraph, color):
    """为段落或单元格设置底纹（用于代码块/表头）。"""
    try:
        # paragraph
        p = cell_or_paragraph._element if hasattr(cell_or_paragraph, "_element") else cell_or_paragraph._tc
        shd = OxmlElement("w:shd")
        shd.set(qn("w:fill"), "{:02X}{:02X}{:02X}".format(color[0], color[1], color[2]))
        p.get_or_add_pPr().append(shd)
    except Exception:
        pass


def parse_inline(paragraph, text):
    """解析行内 **加粗**、*斜体*、`代码`。"""
    # 保护代码片段不被加粗/斜体解析器破坏
    chunks = re.split(r"(`+.+?`+)", text)
    for chunk in chunks:
        if not chunk:
            continue
        if chunk.startswith("`") and chunk.endswith("`"):
            run = paragraph.add_run(chunk[1:-1])
            set_chinese_font(run, "Consolas", 9.5, False, RGBColor(0x3C, 0x4A, 0x55))
            continue
        # 再按 ** 和 * 分段
        sub = re.split(r"(\*\*[^*]+?\*\*|\*[^*]+?\*)", chunk)
        for s in sub:
            if not s:
                continue
            if s.startswith("**") and s.endswith("**"):
                run = paragraph.add_run(s[2:-2])
                set_chinese_font(run, "Microsoft YaHei", 10.5, True, NAVY)
            elif s.startswith("*") and s.endswith("*"):
                run = paragraph.add_run(s[1:-1])
                set_chinese_font(run, "Microsoft YaHei", 10.5, False, NAVY)
                run.font.italic = True
            else:
                run = paragraph.add_run(s)
                set_chinese_font(run, "Microsoft YaHei", 10.5, False, NAVY)


def add_heading(doc, level, text):
    p = doc.add_heading(level=level)
    run = p.add_run(text)
    set_chinese_font(run, "Microsoft YaHei", {1: 18, 2: 15, 3: 13, 4: 11.5}.get(level, 11), True, NAVY)
    p.paragraph_format.space_before = Pt({1: 18, 2: 14, 3: 10, 4: 8}.get(level, 6))
    p.paragraph_format.space_after = Pt({1: 12, 2: 10, 3: 8, 4: 6}.get(level, 4))
    p.paragraph_format.keep_with_next = True
    return p


def add_normal_paragraph(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    p.paragraph_format.space_after = Pt(6)
    parse_inline(p, text)
    return p


def add_code_block(doc, lines):
    """lines 为代码行列表（不含 ```）。"""
    # 用 1×1 无边框表格模拟代码块底纹
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    cell = table.cell(0, 0)
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.TOP
    # 设置单元格底纹
    shading_elm = OxmlElement("w:shd")
    shading_elm.set(qn("w:fill"), "F4F8FB")
    cell._tc.get_or_add_tcPr().append(shading_elm)
    # 设置单元格边距
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement("w:tcMar")
    for side in ("top", "left", "bottom", "right"):
        node = OxmlElement("w:{}".format(side))
        node.set(qn("w:w"), "80")
        node.set(qn("w:type"), "dxa")
        tcMar.append(node)
    tcPr.append(tcMar)
    # 添加代码文本
    for i, line in enumerate(lines):
        if i > 0:
            cell.paragraphs[0].add_run().add_break()
        run = cell.paragraphs[0].add_run(line)
        set_chinese_font(run, "Consolas", 8.5, False, RGBColor(0x3C, 0x4A, 0x55))
    doc.add_paragraph()


def add_markdown_table(doc, lines):
    """lines 为表格所有行（包含表头与分隔行）。"""
    # 过滤空行，解析单元格
    rows = []
    for line in lines:
        line = line.strip()
        if not line or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        rows.append(cells)
    if len(rows) < 2:
        return
    # 第二行是分隔行，丢弃
    header = rows[0]
    body = [r for r in rows[2:] if any(c.strip() for c in r)]
    table = doc.add_table(rows=1 + len(body), cols=len(header))
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    table.allow_autofit = False
    # 表头
    hdr_cells = table.rows[0].cells
    for i, cell_text in enumerate(header):
        if i >= len(hdr_cells):
            break
        cell = hdr_cells[i]
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        shading_elm = OxmlElement("w:shd")
        shading_elm.set(qn("w:fill"), "0F3550")
        cell._tc.get_or_add_tcPr().append(shading_elm)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        run = p.add_run(cell_text)
        set_chinese_font(run, "Microsoft YaHei", 9, True, RGBColor(0xFF, 0xFF, 0xFF))
    # 表体
    for row_idx, row_data in enumerate(body):
        row_cells = table.rows[row_idx + 1].cells
        for i, cell_text in enumerate(row_data):
            if i >= len(row_cells):
                break
            cell = row_cells[i]
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            run = p.add_run()
            set_chinese_font(run, "Microsoft YaHei", 8.5, False, GREY)
            # 单元格内也解析加粗/行内代码
            parse_inline(p, cell_text)
    # 设置列宽大致相等
    for row in table.rows:
        for cell in row.cells:
            cell.width = Cm(2.8)
    doc.add_paragraph()


def add_list_paragraph(doc, text, ordered=False, level=0):
    p = doc.add_paragraph(style="List Number" if ordered else "List Bullet")
    p.paragraph_format.left_indent = Inches(0.25 + level * 0.25)
    p.paragraph_format.space_after = Pt(4)
    content = re.sub(r"^\s*([-*]|\d+\.)\s+", "", text)
    parse_inline(p, content)


def process_blocks(doc, blocks):
    for block in blocks:
        lines = block.splitlines()
        if not lines:
            continue
        first = lines[0]
        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)", first)
        if m:
            level = len(m.group(1))
            add_heading(doc, level, m.group(2).strip())
            # 同一块剩余行作为普通段落（通常无）
            for line in lines[1:]:
                if line.strip():
                    add_normal_paragraph(doc, line.strip())
            continue
        # 代码块
        if first.strip().startswith("```"):
            code_lines = []
            for line in lines[1:]:
                if line.strip().startswith("```"):
                    break
                code_lines.append(line)
            add_code_block(doc, code_lines)
            continue
        # 表格
        if first.strip().startswith("|") and len([l for l in lines if l.strip().startswith("|")]) >= 2:
            add_markdown_table(doc, lines)
            continue
        # 引用块
        if first.strip().startswith(">"):
            text = "\n".join(l.lstrip(">").strip() for l in lines)
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.2)
            p.paragraph_format.space_after = Pt(6)
            run = p.add_run(text)
            set_chinese_font(run, "Microsoft YaHei", 10, False, GREY)
            continue
        # 图片行（单独一行）
        img_match = re.match(r"^\s*!\[(.*?)\]\((.+?)\)\s*$", first)
        if img_match:
            alt, rel_path = img_match.groups()
            img_path = os.path.join(os.path.dirname(MD_PATH), rel_path.replace("/", os.sep))
            if os.path.exists(img_path):
                p = doc.add_paragraph()
                p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                try:
                    run = p.add_run()
                    run.add_picture(img_path, width=Inches(6.2))
                    cap = doc.add_paragraph()
                    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    cr = cap.add_run(alt)
                    set_chinese_font(cr, "Microsoft YaHei", 9, False, GREY)
                except Exception as e:
                    add_normal_paragraph(doc, "[图片嵌入失败: {} - {}]".format(rel_path, e))
            else:
                add_normal_paragraph(doc, "[图片未找到: {}]".format(rel_path))
            continue
        # 列表项（简单处理，支持嵌套缩进）
        if re.match(r"^\s*([-*]|\d+\.)\s+", first):
            for line in lines:
                stripped = line.rstrip()
                if not stripped:
                    continue
                mm = re.match(r"^(\s*)(?:[-*]|\d+\.)\s+(.*)", stripped)
                if mm:
                    level = len(mm.group(1)) // 2
                    ordered = bool(re.match(r"^\s*\d+\.", stripped))
                    add_list_paragraph(doc, stripped, ordered, level)
            continue
        # 普通段落
        text = " ".join(l.strip() for l in lines if l.strip())
        if text:
            add_normal_paragraph(doc, text)


def main():
    doc = Document()
    # 页面 A4，窄边距
    section = doc.sections[0]
    section.page_height = Cm(29.7)
    section.page_width = Cm(21.0)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin = Cm(2.2)
    section.right_margin = Cm(2.2)

    # 设置默认正文字体
    style = doc.styles["Normal"]
    style.font.name = "Microsoft YaHei"
    style._element.rPr.rFonts.set(qn("w:eastAsia"), "Microsoft YaHei")
    style.font.size = Pt(10.5)
    style.font.color.rgb = NAVY

    with open(MD_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # 按空行分块
    raw_blocks = re.split(r"\n\s*\n", content)
    blocks = [b for b in raw_blocks if b.strip()]
    process_blocks(doc, blocks)

    doc.save(OUT_PATH)
    print("saved", OUT_PATH)


if __name__ == "__main__":
    main()
