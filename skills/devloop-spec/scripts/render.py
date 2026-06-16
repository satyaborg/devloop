#!/usr/bin/env python3
"""Render a markdown spec into an interactive HTML companion next to it."""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path


TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{title}</title>
<style>
  :root {{
    --bg: #ffffff;
    --bg-2: #f6f7f9;
    --bg-3: #eceef1;
    --fg: #1a1d21;
    --fg-dim: #4b5563;
    --fg-mute: #6b7280;
    --accent: #0369a1;
    --accent-2: #b45309;
    --good: #16a34a;
    --bad: #dc2626;
    --border: #e2e5ea;
    --mono: ui-monospace, "JetBrains Mono", "SF Mono", Menlo, monospace;
    --sans: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{ background: var(--bg); color: var(--fg); }}
  body {{
    font-family: var(--sans);
    font-size: 15px;
    line-height: 1.6;
    margin: 0;
  }}
  .wrap {{ max-width: 920px; margin: 0 auto; padding: 48px 32px 96px; }}
  header {{ padding-bottom: 14px; margin-bottom: 18px; }}
  .meta {{ font-family: var(--mono); font-size: 12px; color: var(--fg-mute);
           margin-bottom: 8px; letter-spacing: 0.04em; text-transform: uppercase; }}
  h1 {{ font-size: 28px; margin: 0 0 6px; font-weight: 600; letter-spacing: 0; }}
  .subtitle {{ color: var(--fg-dim); font-size: 15px; margin: 0; max-width: 760px; }}
  h3 {{ font-size: 16px; margin: 18px 0 8px; font-weight: 600; color: var(--fg); }}
  h2 {{
    font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em;
    color: var(--fg-mute); margin: 0; padding: 18px 0; cursor: pointer;
    user-select: none; border-top: 1px solid var(--border); display: flex;
    align-items: center; gap: 10px; font-weight: 500;
  }}
  h2:hover {{ color: var(--accent); }}
  h2 .chev {{ display: inline-block; transition: transform 0.15s ease;
              font-family: var(--mono); color: var(--fg-mute); font-size: 11px; }}
  section:first-of-type h2 {{ border-top: 0; padding-top: 0; }}
  section.open h2 .chev {{ transform: rotate(90deg); }}
  section .body {{ display: none; padding: 0 0 28px 24px; }}
  section.open .body {{ display: block; }}

  p {{ margin: 0 0 14px; }}
  a {{ color: var(--accent); text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  strong {{ color: var(--fg); font-weight: 600; }}
  em {{ color: var(--fg-dim); font-style: italic; }}
  code {{
    font-family: var(--mono); font-size: 13px; background: var(--bg-2);
    border: 1px solid var(--border); padding: 1px 6px; border-radius: 4px;
    color: var(--accent);
  }}
  pre {{
    background: var(--bg-2); border: 1px solid var(--border); border-radius: 6px;
    padding: 14px 18px; margin: 0 0 14px; overflow-x: auto;
    font-family: var(--mono); font-size: 12.5px; line-height: 1.6;
  }}
  pre code {{ background: transparent; border: 0; padding: 0; color: var(--fg-dim); }}
  pre.tree {{ font-size: 12.5px; color: var(--fg-dim); }}
  pre.tree .dir {{ color: var(--accent); }}
  pre.tree .file {{ color: var(--fg); }}
  pre.tree .cmt {{ color: var(--fg-mute); }}

  ul, ol {{ padding-left: 22px; margin: 0 0 14px; }}
  li {{ margin-bottom: 6px; }}

  /* mermaid */
  .mermaid-wrap {{
    background: var(--bg-2); border: 1px solid var(--border); border-radius: 8px;
    padding: 18px; margin: 0 0 16px; overflow-x: auto;
  }}
  .mermaid {{ background: transparent !important; }}

  /* acceptance checklist */
  .ac {{ list-style: none; padding: 0; margin: 8px 0 16px; }}
  .ac li {{
    padding: 9px 12px 9px 36px; background: var(--bg-2);
    border: 1px solid var(--border); border-radius: 6px; margin-bottom: 4px;
    position: relative; font-size: 13px; cursor: pointer; user-select: none;
    transition: opacity 0.15s;
  }}
  .ac li::before {{
    content: ""; position: absolute; left: 12px; top: 50%;
    transform: translateY(-50%); width: 14px; height: 14px;
    border: 1px solid var(--border); border-radius: 3px; background: var(--bg-3);
  }}
  .ac li.checked::before {{ background: var(--good); border-color: var(--good); }}
  .ac li.checked::after {{
    content: "\\2713"; position: absolute; left: 14px; top: 50%;
    transform: translateY(-55%); color: var(--bg); font-size: 11px; font-weight: 700;
  }}
  .ac li.checked {{ opacity: 0.5; text-decoration: line-through; }}

  /* numbered stepper */
  .steps {{ list-style: none; padding: 0; margin: 8px 0 16px; counter-reset: step; }}
  .steps li {{
    counter-increment: step; padding: 12px 16px 12px 48px;
    background: var(--bg-2); border: 1px solid var(--border); border-radius: 6px;
    margin-bottom: 6px; position: relative; font-size: 13px; line-height: 1.5;
  }}
  .steps li::before {{
    content: counter(step); position: absolute; left: 14px; top: 12px;
    width: 22px; height: 22px; border-radius: 50%; background: var(--bg-3);
    border: 1px solid var(--border); color: var(--accent);
    font-family: var(--mono); font-size: 11px;
    display: flex; align-items: center; justify-content: center;
  }}

  hr {{ border: 0; border-top: 1px solid var(--border); margin: 18px 0; }}

  footer {{
    margin-top: 48px; padding-top: 18px; border-top: 1px solid var(--border);
    font-family: var(--mono); font-size: 11px; color: var(--fg-mute);
    display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap;
  }}
  footer a {{ color: var(--fg-dim); }}
  footer a:hover {{ color: var(--accent); }}

  @media (max-width: 640px) {{
    .wrap {{ padding: 24px 18px 64px; }}
    h1 {{ font-size: 22px; }}
  }}
</style>
</head>
<body>
<div class="wrap">

<header>
  <div class="meta">{meta}</div>
  <h1>{h1}</h1>
  {subtitle}
</header>

{sections}

<footer>
  <span>{src_path}</span>
  <span>click headings to collapse</span>
</footer>

</div>
{mermaid_script}
<script>
  document.querySelectorAll('section[data-toggle] h2').forEach(h => {{
    h.addEventListener('click', () => h.parentElement.classList.toggle('open'));
  }});
  document.querySelectorAll('.ac li').forEach(li => {{
    li.addEventListener('click', () => li.classList.toggle('checked'));
  }});
</script>
</body>
</html>
"""

MERMAID_SCRIPT = """<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>
  mermaid.initialize({
    startOnLoad: true,
    theme: 'default',
    themeVariables: {
      background: '#ffffff',
      primaryColor: '#f6f7f9',
      primaryTextColor: '#1a1d21',
      primaryBorderColor: '#d1d5db',
      lineColor: '#6b7280',
      secondaryColor: '#eceef1',
      tertiaryColor: '#f6f7f9',
    },
  });
</script>"""


def quote_mermaid_labels(src: str) -> str:
    """Quote Mermaid node labels containing `|`, which Mermaid reserves for edge labels."""
    def repl(m: re.Match[str]) -> str:
        inner = m.group(1)
        if inner[:1] == '"' or "|" not in inner:
            return m.group(0)
        return '["' + inner.replace('"', "'") + '"]'

    return re.sub(r"\[([^\]\n]+)\]", repl, src)


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Return (frontmatter dict, body without frontmatter)."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    raw = text[4:end]
    body = text[end + 5 :]
    fm: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip()
    return fm, body


def split_sections(body: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (preamble, [(h2_title, h2_body), ...]).

    Preamble is anything before the first ## heading (typically the H1 + intro).
    """
    lines = body.splitlines()
    preamble: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    current: tuple[str, list[str]] | None = None
    in_fence = False
    for line in lines:
        if line.startswith("```"):
            in_fence = not in_fence
        if not in_fence and line.startswith("## "):
            if current is not None:
                sections.append(current)
            current = (line[3:].strip(), [])
        elif current is not None:
            current[1].append(line)
        else:
            preamble.append(line)
    if current is not None:
        sections.append(current)
    return "\n".join(preamble), [(t, "\n".join(b).strip()) for t, b in sections]


INLINE_CODE = re.compile(r"`([^`\n]+)`")
BOLD = re.compile(r"\*\*([^*\n]+)\*\*")
ITALIC = re.compile(r"(?<!\*)\*([^*\n]+)\*(?!\*)")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def render_inline(text: str) -> str:
    """Render inline markdown (code, bold, italic, links) into HTML."""
    placeholders: list[str] = []

    def stash(match: re.Match[str], wrap: str) -> str:
        idx = len(placeholders)
        placeholders.append(wrap.format(content=html.escape(match.group(1))))
        return f"\x00{idx}\x00"

    text = INLINE_CODE.sub(lambda m: stash(m, "<code>{content}</code>"), text)

    def link(match: re.Match[str]) -> str:
        idx = len(placeholders)
        placeholders.append(
            f'<a href="{html.escape(match.group(2))}">{html.escape(match.group(1))}</a>'
        )
        return f"\x00{idx}\x00"

    text = LINK.sub(link, text)
    text = html.escape(text)
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = ITALIC.sub(r"<em>\1</em>", text)

    def restore(match: re.Match[str]) -> str:
        return placeholders[int(match.group(1))]

    return re.sub(r"\x00(\d+)\x00", restore, text)


def looks_like_tree(content: str) -> bool:
    """True if a code block looks like a directory tree."""
    lines = [ln for ln in content.splitlines() if ln.strip()]
    if len(lines) < 3:
        return False
    has_dir = any(ln.rstrip().endswith("/") for ln in lines)
    has_indent = any(ln.startswith((" ", "\t")) for ln in lines)
    return has_dir and has_indent


def render_tree(content: str) -> str:
    """Colour a directory-tree-ish code block: dirs in accent, comments in mute."""
    out: list[str] = []
    for line in content.splitlines():
        match = re.match(r"^(\s*)(\S.*?)(\s+#\s.*)?$", line)
        if not match:
            out.append(html.escape(line))
            continue
        indent, body, comment = match.group(1), match.group(2), match.group(3) or ""
        if body.endswith("/"):
            piece = f'<span class="dir">{html.escape(body)}</span>'
        else:
            piece = f'<span class="file">{html.escape(body)}</span>'
        if comment:
            piece += f'<span class="cmt">{html.escape(comment)}</span>'
        out.append(f"{indent}{piece}")
    return "\n".join(out)


UL_RE = re.compile(r"^(\s*)-\s+(?:\[ \]\s+)?(.*)$")
OL_RE = re.compile(r"^(\s*)\d+\.\s+(.*)$")


def parse_list(lines: list[str]) -> list[dict]:
    """Parse a flat list with optional indented children. Returns nested item tree."""
    items: list[dict] = []
    stack: list[tuple[int, dict]] = []
    pending_continuation: dict | None = None

    for ln in lines:
        if not ln.strip():
            continue
        ul = UL_RE.match(ln)
        ol = OL_RE.match(ln)
        if ul or ol:
            match = ul or ol
            indent = len(match.group(1))  # type: ignore[union-attr]
            text = match.group(2)  # type: ignore[union-attr]
            ordered = bool(ol)
            node = {"text": text, "ordered": ordered, "children": []}
            while stack and stack[-1][0] >= indent:
                stack.pop()
            if stack:
                stack[-1][1]["children"].append(node)
            else:
                items.append(node)
            stack.append((indent, node))
            pending_continuation = node
        elif ln.startswith(" ") and pending_continuation is not None:
            pending_continuation["text"] += " " + ln.strip()
    return items


def render_list_items(items: list[dict], *, list_class: str = "") -> str:
    """Render a parsed list tree into nested <ul>/<ol>."""
    if not items:
        return ""
    ordered = items[0]["ordered"]
    tag = "ol" if ordered else "ul"
    cls = f' class="{list_class}"' if list_class else ""
    parts = []
    for item in items:
        child_html = ""
        if item["children"]:
            child_html = render_list_items(item["children"])
        parts.append(f"<li>{render_inline(item['text'])}{child_html}</li>")
    return f"<{tag}{cls}>{''.join(parts)}</{tag}>"


BEHAVIOR_LABELS = {"happy path:", "edge cases:"}
CORE_OPEN_SECTIONS = {
    "problem",
    "outcome",
    "scope",
    "behavior",
    "acceptance criteria",
}


def render_block(
    block: str,
    *,
    in_acceptance: bool,
    in_behavior: bool,
    in_steps: bool,
    h3_steps: bool,
) -> str:
    """Render a single markdown block (paragraph, list, code fence, etc.)."""
    block = block.rstrip()
    if not block.strip():
        return ""

    if block.startswith("```"):
        first_nl = block.find("\n")
        lang = block[3:first_nl].strip() if first_nl != -1 else ""
        end = block.rfind("```")
        content = block[first_nl + 1 : end].rstrip("\n") if first_nl != -1 else ""
        if lang == "mermaid":
            mermaid = html.escape(quote_mermaid_labels(content), quote=False)
            return f'<div class="mermaid-wrap"><pre class="mermaid">{mermaid}</pre></div>'
        if looks_like_tree(content):
            return f'<pre class="tree"><code>{render_tree(content)}</code></pre>'
        return f"<pre><code>{html.escape(content)}</code></pre>"

    lines = block.splitlines()
    first_line = next((ln for ln in lines if ln.strip()), "")
    block_label = block.strip().lower()

    if in_behavior and block_label in BEHAVIOR_LABELS:
        return f"<h3>{render_inline(block.strip().rstrip(':'))}</h3>"

    if UL_RE.match(first_line) or OL_RE.match(first_line):
        items = parse_list(lines)
        ordered = items[0]["ordered"] if items else False
        list_class = ""
        if in_acceptance:
            list_class = "ac"
        elif ordered and (in_steps or h3_steps):
            list_class = "steps"
        return render_list_items(items, list_class=list_class)

    if block.startswith("### "):
        return f"<h3>{render_inline(block[4:].strip())}</h3>"

    if block.strip() == "---":
        return "<hr>"

    paragraph = " ".join(ln.strip() for ln in lines)
    return f"<p>{render_inline(paragraph)}</p>"


def split_blocks(text: str) -> list[str]:
    """Split section body into blocks: paragraphs, lists, code fences."""
    blocks: list[str] = []
    buf: list[str] = []
    in_fence = False

    def flush() -> None:
        if buf:
            blocks.append("\n".join(buf).strip("\n"))
            buf.clear()

    for line in text.splitlines():
        if line.startswith("```"):
            if in_fence:
                buf.append(line)
                in_fence = False
                flush()
            else:
                flush()
                buf.append(line)
                in_fence = True
            continue
        if in_fence:
            buf.append(line)
            continue
        if line.startswith("### "):
            flush()
            buf.append(line)
            flush()
            continue
        if line.strip().lower() in BEHAVIOR_LABELS:
            flush()
            buf.append(line)
            flush()
            continue
        if not line.strip():
            flush()
        else:
            buf.append(line)
    flush()
    return [b for b in blocks if b.strip()]


STEP_KEYWORDS = ("build order", "steps", "build plan")


def render_section(title: str, body: str, *, idx: int) -> str:
    """Render one ## section. Core spec sections open by default."""
    title_lower = title.lower()
    in_acceptance = "acceptance" in title_lower
    in_behavior = title_lower == "behavior"
    in_steps = any(k in title_lower for k in STEP_KEYWORDS)

    blocks = split_blocks(body)
    parts: list[str] = []
    h3_steps = False
    for b in blocks:
        if b.startswith("### "):
            h3_title = b[4:].splitlines()[0].strip().lower()
            h3_steps = any(k in h3_title for k in STEP_KEYWORDS)
        elif not (UL_RE.match(b.splitlines()[0]) or OL_RE.match(b.splitlines()[0])):
            h3_steps = False
        parts.append(
            render_block(
                b,
                in_acceptance=in_acceptance,
                in_behavior=in_behavior,
                in_steps=in_steps,
                h3_steps=h3_steps,
            )
        )
    inner = "\n".join(p for p in parts if p)

    open_cls = "open" if idx < 3 or title_lower in CORE_OPEN_SECTIONS else ""
    cls_attr = f' class="{open_cls}"' if open_cls else ""
    return (
        f"<section{cls_attr} data-toggle>\n"
        f'  <h2><span class="chev">▶</span>{html.escape(title)}</h2>\n'
        f'  <div class="body">{inner}</div>\n'
        f"</section>"
    )


def extract_title_parts(preamble: str) -> tuple[str, str, str]:
    """Return (h1_text, subtitle_text, remaining_preamble)."""
    lines = preamble.splitlines()
    h1 = ""
    rest: list[str] = []
    for line in lines:
        if not h1 and line.startswith("# "):
            h1 = line[2:].strip()
        else:
            rest.append(line)

    subtitle = ""
    subtitle_idx: int | None = None
    for idx, line in enumerate(rest):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(("```", "#", "- ", "* ", ">")) or stripped == "---":
            break
        if re.match(r"^\d+\.\s+", stripped):
            break
        subtitle = stripped
        subtitle_idx = idx
        break

    if subtitle_idx is not None:
        del rest[subtitle_idx]
    return h1, subtitle, "\n".join(rest).strip()


def render_preamble(text: str) -> str:
    """Render the bit between the H1 and the first ## (if any)."""
    if not text.strip():
        return ""
    blocks = split_blocks(text)
    parts = [
        render_block(
            b,
            in_acceptance=False,
            in_behavior=False,
            in_steps=False,
            h3_steps=False,
        )
        for b in blocks
    ]
    return "\n".join(p for p in parts if p)


def build_meta_line(fm: dict[str, str]) -> str:
    """Build the small uppercase meta line under the title."""
    bits = []
    if "created" in fm:
        bits.append(f"created {fm['created']}")
    if "pr" in fm:
        pr = fm["pr"]
        if pr in ("[]", "", "null"):
            bits.append("pr: none")
        else:
            bits.append(f"pr: {pr}")
    bits.append("spec")
    return " · ".join(bits)


def render(md_path: Path) -> Path:
    """Render md_path → sibling .html. Return the HTML path."""
    text = md_path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    preamble, sections = split_sections(body)
    h1, subtitle, intro = extract_title_parts(preamble)
    intro_html = render_preamble(intro)
    section_html = "\n\n".join(
        render_section(title, sec_body, idx=i)
        for i, (title, sec_body) in enumerate(sections)
    )
    rendered_sections = (intro_html + "\n\n" + section_html).strip()

    has_mermaid = "```mermaid" in text
    out = TEMPLATE.format(
        title=html.escape(h1 or md_path.stem),
        h1=html.escape(h1 or md_path.stem),
        subtitle=(
            f'<p class="subtitle">{render_inline(subtitle)}</p>' if subtitle else ""
        ),
        meta=html.escape(build_meta_line(fm)),
        sections=rendered_sections,
        src_path=html.escape(str(md_path)),
        mermaid_script=MERMAID_SCRIPT if has_mermaid else "",
    )
    out_path = md_path.with_suffix(".html")
    out_path.write_text(out, encoding="utf-8")
    return out_path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: render.py <spec.md>", file=sys.stderr)
        return 2
    md_path = Path(sys.argv[1]).expanduser().resolve()
    if not md_path.exists():
        print(f"not found: {md_path}", file=sys.stderr)
        return 1
    out = render(md_path)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
