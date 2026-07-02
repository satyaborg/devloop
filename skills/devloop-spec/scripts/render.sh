#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: render.sh <spec.md>\n' >&2
  exit 2
fi

src="$1"
if [ ! -f "$src" ]; then
  printf 'not found: %s\n' "$src" >&2
  exit 1
fi

src_dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
src_base="$(basename "$src")"
src_path="$src_dir/$src_base"
out_path="$src_dir/${src_base%.*}.html"
tmp_path="$out_path.tmp.$$"

cleanup() {
  rm -f "$tmp_path"
}
trap cleanup EXIT

awk -v src_path="$src_path" -v stem="${src_base%.*}" '
function trim(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/[[:space:]]+$/, "", s)
  return s
}

function append_line(text, line) {
  return text == "" ? line : text "\n" line
}

function append_html(text, part) {
  if (part == "") {
    return text
  }
  return text == "" ? part : text "\n" part
}

function html_escape(s) {
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s)
  return s
}

function render_inline(s) {
  return html_escape(s)
}

function is_ordered(line) {
  return line ~ /^[[:space:]]*[0-9]+[.][[:space:]]+/
}

function is_unordered(line) {
  return line ~ /^[[:space:]]*-[[:space:]]+/
}

function render_list(block, title,    lines, n, i, line, text, current, ordered, tag, class_attr, out, title_lower) {
  n = split(block, lines, "\n")
  ordered = is_ordered(lines[1])
  tag = ordered ? "ol" : "ul"
  title_lower = tolower(title)
  class_attr = ""
  if (index(title_lower, "acceptance") > 0) {
    class_attr = " class=\"ac\""
  } else if (ordered) {
    class_attr = " class=\"steps\""
  }
  out = "<" tag class_attr ">"
  current = ""
  for (i = 1; i <= n; i++) {
    line = lines[i]
    if ((ordered && is_ordered(line)) || (!ordered && is_unordered(line))) {
      if (current != "") {
        out = out "<li>" render_inline(current) "</li>"
      }
      text = line
      if (ordered) {
        sub(/^[[:space:]]*[0-9]+[.][[:space:]]+/, "", text)
      } else {
        sub(/^[[:space:]]*-[[:space:]]+(\[[[:space:]]\][[:space:]]+)?/, "", text)
      }
      current = trim(text)
    } else if (trim(line) != "" && current != "") {
      current = current " " trim(line)
    }
  }
  if (current != "") {
    out = out "<li>" render_inline(current) "</li>"
  }
  return out "</" tag ">"
}

function render_code_block(block,    lines, n, first, lang, content, end, i) {
  n = split(block, lines, "\n")
  first = lines[1]
  lang = trim(substr(first, 4))
  content = ""
  end = n
  if (n > 1 && lines[n] ~ /^```/) {
    end = n - 1
  }
  for (i = 2; i <= end; i++) {
    content = append_line(content, lines[i])
  }
  if (lang == "mermaid") {
    return "<pre class=\"mermaid\">" html_escape(content) "</pre>"
  }
  return "<pre><code>" html_escape(content) "</code></pre>"
}

function render_block(block, title,    lines, first, title_text, paragraph, i) {
  block = trim(block)
  if (block == "") {
    return ""
  }
  split(block, lines, "\n")
  first = lines[1]
  if (first ~ /^```/) {
    return render_code_block(block)
  }
  if (first ~ /^###[[:space:]]+/) {
    title_text = first
    sub(/^###[[:space:]]+/, "", title_text)
    return "<h3>" render_inline(trim(title_text)) "</h3>"
  }
  if (is_unordered(first) || is_ordered(first)) {
    return render_list(block, title)
  }
  if (trim(block) == "---") {
    return "<hr>"
  }
  paragraph = ""
  for (i = 1; i <= split(block, lines, "\n"); i++) {
    paragraph = paragraph == "" ? trim(lines[i]) : paragraph " " trim(lines[i])
  }
  return "<p>" render_inline(paragraph) "</p>"
}

function render_blocks(text, title,    lines, n, i, line, label, block, in_fence, out, title_lower) {
  n = split(text, lines, "\n")
  block = ""
  in_fence = 0
  out = ""
  title_lower = tolower(title)
  for (i = 1; i <= n; i++) {
    line = lines[i]
    if (line ~ /^```/) {
      if (in_fence) {
        block = append_line(block, line)
        in_fence = 0
        out = append_html(out, render_block(block, title))
        block = ""
      } else {
        out = append_html(out, render_block(block, title))
        block = line
        in_fence = 1
      }
      continue
    }
    if (in_fence) {
      block = append_line(block, line)
      continue
    }
    label = tolower(trim(line))
    if (line ~ /^###[[:space:]]+/ || (title_lower == "behavior" && (label == "happy path:" || label == "edge cases:"))) {
      out = append_html(out, render_block(block, title))
      if (title_lower == "behavior" && (label == "happy path:" || label == "edge cases:")) {
        sub(/:$/, "", line)
        out = append_html(out, "<h3>" render_inline(trim(line)) "</h3>")
      } else {
        out = append_html(out, render_block(line, title))
      }
      block = ""
      continue
    }
    if (trim(line) == "") {
      out = append_html(out, render_block(block, title))
      block = ""
    } else {
      block = append_line(block, line)
    }
  }
  out = append_html(out, render_block(block, title))
  return out
}

function extract_preamble(text,    lines, n, i, line, stripped, h1_idx, subtitle_idx) {
  n = split(text, lines, "\n")
  doc_h1 = ""
  doc_subtitle = ""
  doc_intro = ""
  h1_idx = 0
  subtitle_idx = 0
  for (i = 1; i <= n; i++) {
    line = lines[i]
    if (doc_h1 == "" && line ~ /^#[[:space:]]+/) {
      doc_h1 = trim(substr(line, 3))
      h1_idx = i
      break
    }
  }
  for (i = 1; i <= n; i++) {
    if (i == h1_idx) {
      continue
    }
    stripped = trim(lines[i])
    if (stripped == "") {
      continue
    }
    if (stripped ~ /^```/ || stripped ~ /^#/ || stripped ~ /^-/ || stripped ~ /^[*]/ || stripped ~ /^>/ || stripped == "---" || stripped ~ /^[0-9]+[.][[:space:]]+/) {
      break
    }
    doc_subtitle = stripped
    subtitle_idx = i
    break
  }
  for (i = 1; i <= n; i++) {
    if (i == h1_idx || i == subtitle_idx) {
      continue
    }
    doc_intro = append_line(doc_intro, lines[i])
  }
}

function meta_line(    out) {
  out = ""
  if (fm_created != "") {
    out = "created " fm_created
  }
  if (fm_pr != "") {
    out = out == "" ? "" : out " | "
    out = out (fm_pr == "[]" || fm_pr == "null" ? "pr: none" : "pr: " fm_pr)
  }
  out = out == "" ? "spec" : out " | spec"
  return out
}

function section_is_open(title, idx,    lower) {
  lower = tolower(title)
  return idx < 3 || lower == "problem" || lower == "outcome" || lower == "scope" || lower == "behavior" || lower == "acceptance criteria"
}

function render_section(title, body, idx,    inner, attrs) {
  inner = render_blocks(body, title)
  attrs = section_is_open(title, idx) ? " class=\"section open\" open" : " class=\"section\""
  return "<details" attrs ">\n  <summary><span class=\"chev\">▶</span>" html_escape(title) "</summary>\n  <div class=\"body\">" inner "</div>\n</details>"
}

function print_css() {
  print "<style>"
  print "  :root {"
  print "    --bg: #ffffff;"
  print "    --bg-2: #f6f7f9;"
  print "    --bg-3: #eceef1;"
  print "    --fg: #1a1d21;"
  print "    --fg-dim: #4b5563;"
  print "    --fg-mute: #6b7280;"
  print "    --accent: #0369a1;"
  print "    --good: #16a34a;"
  print "    --border: #e2e5ea;"
  print "    --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;"
  print "    --sans: -apple-system, BlinkMacSystemFont, Inter, system-ui, sans-serif;"
  print "  }"
  print "  * { box-sizing: border-box; }"
  print "  html, body { background: var(--bg); color: var(--fg); }"
  print "  body { font-family: var(--sans); font-size: 15px; line-height: 1.6; margin: 0; }"
  print "  .wrap { max-width: 920px; margin: 0 auto; padding: 48px 32px 96px; }"
  print "  header { padding-bottom: 14px; margin-bottom: 18px; }"
  print "  .meta { font-family: var(--mono); font-size: 12px; color: var(--fg-mute); margin-bottom: 8px; letter-spacing: 0.04em; text-transform: uppercase; }"
  print "  h1 { font-size: 28px; margin: 0 0 6px; font-weight: 600; letter-spacing: 0; }"
  print "  .subtitle { color: var(--fg-dim); font-size: 15px; margin: 0; max-width: 760px; }"
  print "  h3 { font-size: 16px; margin: 18px 0 8px; font-weight: 600; color: var(--fg); }"
  print "  details.section { border-top: 1px solid var(--border); }"
  print "  details.section:first-of-type { border-top: 0; }"
  print "  summary { font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--fg-mute); margin: 0; padding: 18px 0; cursor: pointer; user-select: none; display: flex; align-items: center; gap: 10px; font-weight: 500; list-style: none; }"
  print "  summary::-webkit-details-marker { display: none; }"
  print "  summary:hover { color: var(--accent); }"
  print "  .chev { display: inline-block; transition: transform 0.15s ease; font-family: var(--mono); color: var(--fg-mute); font-size: 11px; }"
  print "  details[open] .chev { transform: rotate(90deg); }"
  print "  .body { padding: 0 0 28px 24px; }"
  print "  p { margin: 0 0 14px; }"
  print "  a { color: var(--accent); text-decoration: none; }"
  print "  code { font-family: var(--mono); font-size: 13px; background: var(--bg-2); border: 1px solid var(--border); padding: 1px 6px; border-radius: 4px; color: var(--accent); }"
  print "  pre { background: var(--bg-2); border: 1px solid var(--border); border-radius: 6px; padding: 14px 18px; margin: 0 0 14px; overflow-x: auto; font-family: var(--mono); font-size: 12.5px; line-height: 1.6; }"
  print "  pre code { background: transparent; border: 0; padding: 0; color: var(--fg-dim); }"
  print "  pre.mermaid { color: var(--fg-dim); }"
  print "  ul, ol { padding-left: 22px; margin: 0 0 14px; }"
  print "  li { margin-bottom: 6px; }"
  print "  .ac { list-style: none; padding: 0; margin: 8px 0 16px; }"
  print "  .ac li { padding: 9px 12px; background: var(--bg-2); border: 1px solid var(--border); border-radius: 6px; margin-bottom: 4px; font-size: 13px; }"
  print "  .steps { list-style: decimal; }"
  print "  hr { border: 0; border-top: 1px solid var(--border); margin: 18px 0; }"
  print "  footer { margin-top: 48px; padding-top: 18px; border-top: 1px solid var(--border); font-family: var(--mono); font-size: 11px; color: var(--fg-mute); display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; }"
  print "  @media (max-width: 640px) { .wrap { padding: 24px 18px 64px; } h1 { font-size: 22px; } }"
  print "</style>"
}

function print_mermaid_script() {
  print "<script type=\"module\">"
  print "  import mermaid from \"https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs\";"
  print "  mermaid.initialize({ startOnLoad: true, theme: \"default\" });"
  print "</script>"
}

{
  lines[NR] = $0
  if ($0 ~ /^```[[:space:]]*mermaid[[:space:]]*$/) {
    has_mermaid = 1
  }
}

END {
  body_start = 1
  if (lines[1] == "---") {
    for (i = 2; i <= NR; i++) {
      if (lines[i] == "---") {
        frontmatter_end = i
        break
      }
    }
    if (frontmatter_end > 0) {
      for (i = 2; i < frontmatter_end; i++) {
        colon = index(lines[i], ":")
        if (colon > 0) {
          key = trim(substr(lines[i], 1, colon - 1))
          value = trim(substr(lines[i], colon + 1))
          if (key == "created") {
            fm_created = value
          } else if (key == "pr") {
            fm_pr = value
          }
        }
      }
      body_start = frontmatter_end + 1
    }
  }

  in_fence = 0
  current = 0
  for (i = body_start; i <= NR; i++) {
    line = lines[i]
    if (line ~ /^```/) {
      in_fence = !in_fence
    }
    if (!in_fence && line ~ /^##[[:space:]]+/) {
      current++
      section_title[current] = trim(substr(line, 4))
      section_body[current] = ""
    } else if (current > 0) {
      section_body[current] = append_line(section_body[current], line)
    } else {
      preamble = append_line(preamble, line)
    }
  }

  extract_preamble(preamble)
  if (doc_h1 == "") {
    doc_h1 = stem
  }
  sections_html = render_blocks(doc_intro, "")
  for (i = 1; i <= current; i++) {
    sections_html = append_html(sections_html, render_section(section_title[i], section_body[i], i - 1))
  }

  print "<!DOCTYPE html>"
  print "<html lang=\"en\">"
  print "<head>"
  print "<meta charset=\"UTF-8\">"
  print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
  print "<title>" html_escape(doc_h1) "</title>"
  print_css()
  print "</head>"
  print "<body>"
  print "<div class=\"wrap\">"
  print "<header>"
  print "  <div class=\"meta\">" html_escape(meta_line()) "</div>"
  print "  <h1>" html_escape(doc_h1) "</h1>"
  if (doc_subtitle != "") {
    print "  <p class=\"subtitle\">" render_inline(doc_subtitle) "</p>"
  }
  print "</header>"
  print sections_html
  print "<footer>"
  print "  <span>" html_escape(src_path) "</span>"
  print "  <span>sections use native details</span>"
  print "</footer>"
  print "</div>"
  if (has_mermaid) {
    print_mermaid_script()
  }
  print "</body>"
  print "</html>"
}
' "$src_path" > "$tmp_path"

mv "$tmp_path" "$out_path"
trap - EXIT
printf '%s\n' "$out_path"
