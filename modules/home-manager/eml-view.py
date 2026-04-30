#!/usr/bin/env python3
"""Render a .eml (RFC 822) message as a standalone HTML file and hand it to a
browser. No mail client required; Python stdlib only.

Usage: eml-view <path-to.eml> [browser]
  browser defaults to $EML_VIEW_BROWSER, then zen-beta, then xdg-open.
"""

from __future__ import annotations

import base64
import email
import email.policy
import html as html_mod
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


HEADERS_TO_SHOW = ("From", "To", "Cc", "Subject", "Date")


def _pick_browser(explicit: str | None) -> list[str]:
    if explicit:
        return [explicit]
    env = os.environ.get("EML_VIEW_BROWSER")
    if env:
        return [env]
    for candidate in ("zen-beta", "xdg-open"):
        if shutil.which(candidate):
            return [candidate]
    print("error: no browser found (tried zen-beta, xdg-open)", file=sys.stderr)
    sys.exit(1)


def _body_html(msg: email.message.EmailMessage) -> tuple[str, bool]:
    """Return (html_fragment, was_html)."""
    body = msg.get_body(preferencelist=("html", "plain"))
    if body is None:
        return ("<p><em>(no body)</em></p>", False)
    content = body.get_content()
    if body.get_content_type() == "text/html":
        return (content, True)
    return (f"<pre>{html_mod.escape(content)}</pre>", False)


def _inline_cid_images(html: str, msg: email.message.EmailMessage) -> str:
    cid_parts: dict[str, email.message.EmailMessage] = {}
    for part in msg.walk():
        cid = part.get("Content-ID")
        if cid and part.get_content_maintype() == "image":
            cid_parts[cid.strip("<>")] = part

    if not cid_parts:
        return html

    def replace(match: re.Match[str]) -> str:
        cid = match.group(1)
        part = cid_parts.get(cid)
        if part is None:
            return match.group(0)
        payload = part.get_payload(decode=True)
        if payload is None:
            return match.group(0)
        mime = part.get_content_type()
        b64 = base64.b64encode(payload).decode("ascii")
        return f'src="data:{mime};base64,{b64}"'

    return re.sub(r'src="cid:([^"]+)"', replace, html, flags=re.IGNORECASE)


def _attachments_list(msg: email.message.EmailMessage) -> str:
    items: list[str] = []
    for part in msg.iter_attachments():
        name = part.get_filename() or "(unnamed)"
        size = len(part.get_payload(decode=True) or b"")
        items.append(
            f"<li>{html_mod.escape(name)} "
            f"<span class=meta>({part.get_content_type()}, {size:,} bytes)</span></li>"
        )
    if not items:
        return ""
    return (
        '<details class="attachments"><summary>'
        f"Attachments ({len(items)})</summary><ul>"
        + "".join(items)
        + "</ul></details>"
    )


def _headers_block(msg: email.message.EmailMessage) -> str:
    rows: list[str] = []
    for h in HEADERS_TO_SHOW:
        val = msg.get(h)
        if not val:
            continue
        rows.append(
            f"<div><span class=k>{h}</span>"
            f"<span class=v>{html_mod.escape(str(val))}</span></div>"
        )
    return f'<div class="hdr">{"".join(rows)}</div>'


STYLE = """
:root { color-scheme: light dark; }
body { font-family: -apple-system, system-ui, sans-serif; max-width: 820px;
       margin: 2em auto; padding: 0 1em; line-height: 1.5; }
.hdr { border: 1px solid #8884; border-radius: 8px; padding: .75em 1em;
       margin-bottom: 1.25em; font-size: .92em; }
.hdr > div { display: flex; gap: .5em; padding: 2px 0; }
.hdr .k { min-width: 5em; color: #8a8a8a; font-variant: small-caps;
          letter-spacing: .05em; }
.hdr .v { flex: 1; word-break: break-word; }
.attachments { margin: 1em 0; padding: .5em 1em; border: 1px dashed #8884;
               border-radius: 6px; }
.attachments .meta { color: #888; font-size: .85em; }
pre { white-space: pre-wrap; word-break: break-word; }
img { max-width: 100%; height: auto; }
"""


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__, file=sys.stderr)
        return 2

    src = pathlib.Path(sys.argv[1]).expanduser()
    browser_override = sys.argv[2] if len(sys.argv) > 2 else None

    if not src.is_file():
        print(f"error: not a file: {src}", file=sys.stderr)
        return 1

    msg = email.message_from_bytes(src.read_bytes(), policy=email.policy.default)
    body_html, _ = _body_html(msg)
    body_html = _inline_cid_images(body_html, msg)

    title = html_mod.escape(str(msg.get("Subject") or src.name))
    document = (
        "<!doctype html><html><head><meta charset=utf-8>"
        f"<title>{title}</title><style>{STYLE}</style></head><body>"
        f"{_headers_block(msg)}"
        f"{_attachments_list(msg)}"
        f"<main>{body_html}</main>"
        "</body></html>"
    )

    out = tempfile.NamedTemporaryFile(
        prefix="eml-view-",
        suffix=".html",
        delete=False,
        mode="w",
        encoding="utf-8",
    )
    out.write(document)
    out.close()

    cmd = _pick_browser(browser_override) + [out.name]
    subprocess.Popen(cmd, start_new_session=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
