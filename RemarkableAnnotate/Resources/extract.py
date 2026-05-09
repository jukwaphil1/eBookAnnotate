#!/usr/bin/env python3
"""
RemarkableAnnotate — extract highlighted text from reMarkable PDFs via USB web interface.

The reMarkable USB web interface runs at http://10.11.99.1 when the device is connected
via USB. No SSH, no Developer Mode, no password required.

Usage:
  python3 extract.py list    <host>
  python3 extract.py extract <host> <uuid> <output_path>
"""

import sys
import json
import io
import os
import zipfile
import tempfile

BASE_URL = "http://{host}"


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def get_json(host, path):
    import requests
    resp = requests.get(f"http://{host}{path}", timeout=10)
    resp.raise_for_status()
    return resp.json()


def download_bytes(host, path, timeout=120):
    import requests
    resp = requests.get(f"http://{host}{path}", timeout=timeout, stream=True)
    resp.raise_for_status()
    buf = io.BytesIO()
    for chunk in resp.iter_content(chunk_size=65536):
        buf.write(chunk)
    buf.seek(0)
    return buf


# ---------------------------------------------------------------------------
# .rmdoc zip helpers
# ---------------------------------------------------------------------------

def read_zip_json(zf, name):
    try:
        with zf.open(name) as f:
            return json.load(f)
    except Exception:
        return None


def page_list(content):
    """Return list of {id, pdf_index} from .content JSON."""
    c_pages = content.get("cPages", {}).get("pages", [])
    if c_pages:
        result = []
        for i, p in enumerate(c_pages):
            result.append({
                "id": p.get("id", ""),
                "pdf_index": p.get("idx", {}).get("value", i) if isinstance(p.get("idx"), dict) else i,
            })
        return result
    old = content.get("pages", [])
    return [{"id": pid, "pdf_index": i} for i, pid in enumerate(old)]


# ---------------------------------------------------------------------------
# .rm highlight parsing (rmscene)
# ---------------------------------------------------------------------------

def highlight_boxes(rm_bytes):
    """Return list of (x0,y0,x1,y1) bounding boxes for highlight strokes."""
    try:
        import rmscene
        from rmscene import read_blocks, SceneLineItemBlock
        blocks = list(read_blocks(io.BytesIO(rm_bytes)))
    except Exception:
        return []

    boxes = []
    for block in blocks:
        if not isinstance(block, SceneLineItemBlock) or block.value is None:
            continue
        line = block.value
        if not _is_highlighter(line.tool):
            continue
        pts = line.points
        if not pts:
            continue
        xs = [p.x for p in pts]
        ys = [p.y for p in pts]
        boxes.append((min(xs), min(ys), max(xs), max(ys)))
    return boxes


def _is_highlighter(tool):
    try:
        import rmscene
        if tool == rmscene.Pen.HIGHLIGHTER:
            return True
    except Exception:
        pass
    return "HIGHLIGHTER" in str(tool).upper()


# ---------------------------------------------------------------------------
# list command
# ---------------------------------------------------------------------------

def cmd_list(host):
    docs = get_json(host, "/documents/")
    result = []
    for d in docs:
        if d.get("Type") != "DocumentType":
            continue
        result.append({
            "uuid": d["ID"],
            "title": d.get("VissibleName", "Untitled"),
        })
    result.sort(key=lambda d: d["title"].lower())
    _ok({"documents": result})


# ---------------------------------------------------------------------------
# extract command
# ---------------------------------------------------------------------------

def cmd_extract(host, uuid, output_path):
    import fitz  # PyMuPDF

    rmdoc_buf = download_bytes(host, f"/download/{uuid}/rmdoc")

    with zipfile.ZipFile(rmdoc_buf) as zf:
        names = zf.namelist()

        # Find the .content and .pdf files (may be at root or inside a folder)
        content_name = _find(names, lambda n: n.endswith(".content"))
        pdf_name = _find(names, lambda n: n.endswith(".pdf"))

        if not content_name:
            _err("No .content file found in rmdoc bundle")
        if not pdf_name:
            _err("No PDF found in rmdoc bundle — document may not be a PDF annotation")

        content = read_zip_json(zf, content_name)
        if not content:
            _err("Could not read .content file")

        # Derive the UUID prefix used for page files
        prefix = content_name[:-len(".content")]  # e.g. "abc123" or "folder/abc123"

        # Extract PDF to temp file
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
            tmp_path = tmp.name
        with zf.open(pdf_name) as src, open(tmp_path, "wb") as dst:
            dst.write(src.read())

        pdf_doc = fitz.open(tmp_path)
        pages = page_list(content)

        hits = []
        for pg in pages:
            rm_name = f"{prefix}/{pg['id']}.rm"
            if rm_name not in names:
                # Try without subfolder (some older bundles)
                rm_name = f"{pg['id']}.rm"
            if rm_name not in names:
                continue

            pdf_idx = pg["pdf_index"]
            if pdf_idx >= len(pdf_doc):
                continue

            with zf.open(rm_name) as f:
                rm_bytes = f.read()

            pdf_page = pdf_doc[pdf_idx]
            for text in _texts_for_page(rm_bytes, pdf_page):
                hits.append((pdf_idx + 1, text))

        pdf_doc.close()
        os.unlink(tmp_path)

    # Write Markdown
    title = _find_title(host, uuid)
    _write_markdown(output_path, title, hits)
    _ok({"highlight_count": len(hits)})


def _find_title(host, uuid):
    try:
        docs = get_json(host, "/documents/")
        for d in docs:
            if d.get("ID") == uuid:
                return d.get("VissibleName", "Untitled")
    except Exception:
        pass
    return "Untitled"


def _find(names, predicate):
    return next((n for n in names if predicate(n)), None)


def _texts_for_page(rm_bytes, pdf_page):
    import fitz
    boxes = highlight_boxes(rm_bytes)
    scale = pdf_page.rect.width / 1404.0
    texts = []
    for (x0, y0, x1, y1) in boxes:
        rect = fitz.Rect(x0 * scale - 2, y0 * scale - 2, x1 * scale + 2, y1 * scale + 2)
        rect = rect & pdf_page.rect
        if rect.is_empty:
            continue
        text = pdf_page.get_text("text", clip=rect).strip()
        if text:
            texts.append(text)
    return texts


def _write_markdown(path, title, hits):
    lines = [f"# {title}\n"]
    current_page = None
    for page_num, text in hits:
        if page_num != current_page:
            current_page = page_num
            lines.append(f"\n## Page {page_num}\n")
        inline = " ".join(text.split())
        lines.append(f"> {inline}\n")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

def _ok(extra=None):
    payload = {"status": "ok"}
    if extra:
        payload.update(extra)
    print(json.dumps(payload))


def _err(msg):
    print(json.dumps({"status": "error", "message": msg}))
    sys.exit(1)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 3:
        _err("Usage: extract.py <list|extract> <host> [uuid output_path]")

    command, host = sys.argv[1], sys.argv[2]

    try:
        if command == "list":
            cmd_list(host)
        elif command == "extract":
            if len(sys.argv) < 5:
                _err("extract requires <uuid> and <output_path>")
            cmd_extract(host, sys.argv[3], sys.argv[4])
        else:
            _err(f"Unknown command: {command}")
    except Exception as e:
        _err(str(e))
