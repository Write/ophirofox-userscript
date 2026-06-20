#!/usr/bin/env python3
"""
Transform ophirofox content_script JS → userscript-compatible JS.
Replaces chrome.storage.sync (unavailable in userscripts) with GM.* equivalents
and configurationsSpecifiques() with getOphirofoxConfig() + property check.

Usage: python3 adapt-special-case.py <site_type> < input.js > output.js
  site_type: mediapart | arretsurimages | alternativeseconomiques
"""
import sys, re

SITE = sys.argv[1] if len(sys.argv) > 1 else ""

code = sys.stdin.read()

# ── Helper: extract quoted keys from ["k1", 'k2'] strings ────────────────────
def _extract_keys(s):
    return re.findall(r"""['"]([^'"]+)['"]""", s)

# ── 1. configurationsSpecifiques([...]) → getOphirofoxConfig() ──────────────
code = re.sub(
    r"const config = await configurationsSpecifiques\(\[.*?\]\);?",
    "const config = await getOphirofoxConfig();",
    code,
)

# ── 2. if (!config) → property check (site-specific) ────────────────────────
PROPERTY_MAP = {
    "mediapart": "AUTH_URL_MEDIAPART",
    "arretsurimages": "AUTH_URL_ARRETSURIMAGES",
    "alternativeseconomiques": "AUTH_URL_ALTERNATIVESECONOMIQUES",
    "pressreader": "AUTH_URL_PRESSREADER",
}
prop = PROPERTY_MAP.get(SITE)
if prop:
    code = re.sub(r"if\s*\(!config\)\s*return;", f"if (!config.{prop}) return;", code)
    code = re.sub(r"if\s*\(!config\)\s*\{", f"if (!config.{prop}) {{", code)

# ── 3. chrome.storage.sync.remove(["k1","k2"]) → GM.deleteValue(...) ────────
def _replace_remove(m):
    indent = m.group(1)
    has_await = bool(m.group(2))
    keys = _extract_keys(m.group(3))
    prefix = "await " if has_await else ""
    return "\n".join(f"{indent}{prefix}GM.deleteValue(\"{k}\");" for k in keys)

code = re.sub(
    r"(\s*)(await\s+)?chrome\.storage\.sync\.remove\(\s*\[(.*?)\]\s*\);?",

    _replace_remove,
    code,
    flags=re.DOTALL,
)

# ── 4. chrome.storage.sync.set({...}) → GM.setValue(...) ────────────────────
def _replace_set(m):
    indent = m.group(1)
    has_await = bool(m.group(2))
    inner = m.group(3)
    pairs = re.findall(r"""['"]([^'"]+)['"]\s*:\s*(.+?)\s*(?:,|$)""", inner, re.DOTALL)
    prefix = "await " if has_await else ""
    lines = []
    for k, v in pairs:
        v = v.strip().rstrip(",")
        lines.append(f"{indent}{prefix}GM.setValue(\"{k}\", {v});")
    return "\n".join(lines)

code = re.sub(
    r"(\s*)(await\s+)?chrome\.storage\.sync\.set\(\s*\{(.*?)\}\s*\);?",

    _replace_set,
    code,
    flags=re.DOTALL,
)

# ── 5. chrome.storage.sync.get(...).then(...) → GM.getValue(...) ───────────
# Handles:  let articlePath;\n  await chrome.storage.sync.get(...).then(...)
def _replace_get_then(m):
    let_indent = m.group(1) or ""   # indent of optional "let x;" line
    let_var = m.group(2) or ""       # variable name from "let x;"
    await_indent = m.group(3) or ""  # indent of "await chrome..." line
    keys_str = m.group(4)
    body = m.group(5)
    indent = let_indent or await_indent
    keys = _extract_keys(keys_str)
    lines = []
    for k in keys:
        # Find variable assigned from result.KEY
        vm = re.search(r"(\w+)\s*=\s*result\." + re.escape(k), body)
        if vm:
            varname = vm.group(1)
            lines.append(f"{indent}const {varname} = await GM.getValue(\"{k}\", null);")
    return "\n".join(lines)

code = re.sub(
    r"(?:(\s*)let\s+(\w+);\s*\n)?"              # optional preceding let declaration
    r"(\s*)await chrome\.storage\.sync\.get\(\s*\[(.*?)\]\s*\)"
    r"\.then\(\s*\(result\)\s*=>\s*\{(.*?)\}\s*\);?",

    _replace_get_then,
    code,
    flags=re.DOTALL,
)

# ── 6. const { key: var } = await chrome.storage.sync.get([...]) ────────────
def _replace_get_destructure(m):
    indent = m.group(1)
    destructure = m.group(2)
    keys_str = m.group(3)  # captured but unused — destructured names ARE the keys
    parts = re.findall(r"(\w+)\s*:\s*(\w+)", destructure)
    lines = []
    for storage_key, var_name in parts:
        lines.append(f"{indent}const {var_name} = await GM.getValue(\"{storage_key}\", null);")
    return "\n".join(lines)

code = re.sub(
    r"(\s*)const\s*\{(.*?)\}\s*=\s*await chrome\.storage\.sync\.get\(\s*\[(.*?)\]\s*\);?",
    _replace_get_destructure,
    code,
)

# ── 7. Cleanup ───────────────────────────────────────────────────────────────
code = re.sub(r"await\s+await\s+", "await ", code)

sys.stdout.write(code)
