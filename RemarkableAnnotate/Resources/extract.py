#!/usr/bin/env python3
"""
RemarkableAnnotate — extract highlighted text from reMarkable 2 PDFs over SSH.

Usage:
  python3 extract.py list    <host> <password>
  python3 extract.py extract <host> <password> <uuid> <output_path>
"""

import sys
import json
import io
import os
import tempfile

XOCHITL = "/home/root/.local/share/remarkable/xochitl"


# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

def ssh_connect(host, password):
    import paramiko
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username="root", password=password, timeout=10)
    return client


def read_remote_json(sftp, path):
    try:
        with sftp.open(path) as f:
            return json.load(f)
    except Exception:
        return None


# ---------------------------------------------------------------------------
# reMarkable page list helpers
# ---------------------------------------------------------------------------

def page_list(content):
    """Return list of {id, pdf_index} dicts from a .content JSON object."""
    # New firmware: cPages.pages[].{id, idx.value}
    c_pages = content.get("cPages", {}).get("pages", [])
    if c_pages:
        result = []
        for i, p in enumerate(c_pages):
            result.append({"id": p.get("id", ""), "pdf_index": p.get("idx", {}).get("value", i)})
        return result

    # Older firmware: pages[] is a flat list of UUIDs
    old = content.get("pages", [])
    return [{"id": pid, "pdf_index": i} for i, pid in enumerate(old)]


# ---------------------------------------------------------------------------
# .rm highlight parsing
# ---------------------------------------------------------------------------

def highlights_in_rm_bytes(data):
    """Return list of (x0,y0,x1,y1) bounding boxes for highlight strokes."""
    try:
        import rmscene
        from rmscene import read_blocks, SceneLineItemBlock
        blocks = list(read_blocks(io.BytesIO(data)))
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


def highlight_count_in_rm_bytes(data):
    return len(highlights_in_rm_bytes(data))


# ---------------------------------------------------------------------------
# list command
# ---------------------------------------------------------------------------

def cmd_list(host, password):
    client = ssh_connect(host, password)
    sftp = client.open_sftp()
    try:
        entries = sftp.listdir(XOCHITL)
        uuids = [e[:-9] for e in entries if e.endswith(".metadata")]

        documents = []
        for uuid in uuids:
            meta = read_remote_json(sftp, f"{XOCHITL}/{uuid}.metadata")
            if not meta or meta.get("type") != "DocumentType":
                continue

            content = read_remote_json(sftp, f"{XOCHITL}/{uuid}.content")
            if not content or content.get("fileType") != "pdf":
                continue

            pages = page_list(content)
            total_highlights = 0
            for pg in pages:
                rm_path = f"{XOCHITL}/{uuid}/{pg['id']}.rm"
                try:
                    with sftp.open(rm_path, "rb") as f:
                        data = f.read()
                    total_highlights += highlight_count_in_rm_bytes(data)
                except Exception:
                    pass

            if total_highlights == 0:
                continue

            documents.append({
                "uuid": uuid,
                "title": meta.get("visibleName", "Untitled"),
                "highlight_count": total_highlights,
                "page_count": len(pages),
            })

        documents.sort(key=lambda d: d["title"].lower())
        _ok({"documents": documents})
    finally:
        sftp.close()
        client.close()


# ---------------------------------------------------------------------------
# extract command
# ---------------------------------------------------------------------------

def cmd_extract(host, password, uuid, output_path):
    import fitz  # PyMuPDF

    client = ssh_connect(host, password)
    sftp = client.open_sftp()
    try:
        meta = read_remote_json(sftp, f"{XOCHITL}/{uuid}.metadata")
        content = read_remote_json(sftp, f"{XOCHITL}/{uuid}.content")
        title = meta.get("visibleName", "Untitled") if meta else "Untitled"

        tmp_pdf = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
        tmp_pdf.close()
        sftp.get(f"{XOCHITL}/{uuid}.pdf", tmp_pdf.name)

        pdf_doc = fitz.open(tmp_pdf.name)
        pages = page_list(content or {})

        # Collect (1-based page num, text) tuples
        hits = []
        for pg in pages:
            rm_path = f"{XOCHITL}/{uuid}/{pg['id']}.rm"
            try:
                with sftp.open(rm_path, "rb") as f:
                    rm_data = f.read()
            except Exception:
                continue

            pdf_idx = pg["pdf_index"]
            if pdf_idx >= len(pdf_doc):
                continue

            pdf_page = pdf_doc[pdf_idx]
            for text in _texts_for_page(rm_data, pdf_page):
                hits.append((pdf_idx + 1, text))

        pdf_doc.close()
        os.unlink(tmp_pdf.name)

        _write_markdown(output_path, title, hits)
        _ok({"highlight_count": len(hits)})
    finally:
        sftp.close()
        client.close()


def _texts_for_page(rm_data, pdf_page):
    import fitz
    boxes = highlights_in_rm_bytes(rm_data)
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
        # Collapse internal newlines for inline quote
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
    if len(sys.argv) < 4:
        _err("Usage: extract.py <list|extract> <host> <password> [uuid output_path]")

    command, host, password = sys.argv[1], sys.argv[2], sys.argv[3]

    try:
        if command == "list":
            cmd_list(host, password)
        elif command == "extract":
            if len(sys.argv) < 6:
                _err("extract requires <uuid> and <output_path>")
            cmd_extract(host, password, sys.argv[4], sys.argv[5])
        else:
            _err(f"Unknown command: {command}")
    except Exception as e:
        _err(str(e))
