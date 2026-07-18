#!/usr/bin/env python3
"""Best-effort Lua deobfuscator for the local DST pvp mod.

This tool is intentionally conservative: it reads the live `pvp` mod and
writes readable copies under the repository-level `docs/pvp/deobfuscated/`.
"""
from __future__ import annotations

import ast
import operator
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MOD_ROOT = REPO_ROOT / "pvp"
INPUT = MOD_ROOT / "modmain.lua"
OUTPUT_DIR = REPO_ROOT / "docs" / "pvp" / "deobfuscated"
OUTPUT = OUTPUT_DIR / "modmain.lua"
SUMMARY = OUTPUT_DIR / "summary.md"

BIN_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
}
CMP_OPS = {
    ast.Eq: operator.eq,
    ast.NotEq: operator.ne,
    ast.Lt: operator.lt,
    ast.LtE: operator.le,
    ast.Gt: operator.gt,
    ast.GtE: operator.ge,
}


def eval_num_expr(expr: str):
    expr = expr.strip()
    if not re.fullmatch(r"[0-9+\-*/%().\s]+", expr):
        raise ValueError(expr)
    node = ast.parse(expr, mode="eval").body

    def walk(n):
        if isinstance(n, ast.Constant) and isinstance(n.value, (int, float)):
            return n.value
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.USub):
            return -walk(n.operand)
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.UAdd):
            return walk(n.operand)
        if isinstance(n, ast.BinOp) and type(n.op) in BIN_OPS:
            return BIN_OPS[type(n.op)](walk(n.left), walk(n.right))
        raise ValueError(expr)

    return walk(node)


def eval_bool_expr(expr: str):
    node = ast.parse(expr, mode="eval").body
    if not isinstance(node, ast.Compare) or len(node.ops) != 1 or len(node.comparators) != 1:
        raise ValueError(expr)
    op = type(node.ops[0])
    if op not in CMP_OPS:
        raise ValueError(expr)
    left = eval_num_expr(ast.unparse(node.left))
    right = eval_num_expr(ast.unparse(node.comparators[0]))
    return CMP_OPS[op](left, right)


def lua_unescape(content: str) -> str:
    out = bytearray()
    i = 0
    while i < len(content):
        ch = content[i]
        if ch != "\\":
            out.extend(ch.encode("utf-8"))
            i += 1
            continue
        i += 1
        if i >= len(content):
            out.append(ord("\\"))
            break
        esc = content[i]
        if esc.isdigit():
            j = i
            while j < len(content) and content[j].isdigit() and j - i < 3:
                j += 1
            out.append(int(content[i:j]) & 0xFF)
            i = j
        else:
            table = {
                "a": 7,
                "b": 8,
                "f": 12,
                "n": 10,
                "r": 13,
                "t": 9,
                "v": 11,
                "\\": 92,
                '"': 34,
                "'": 39,
            }
            if esc in table:
                out.append(table[esc])
            else:
                out.extend(esc.encode("utf-8"))
            i += 1
    return out.decode("utf-8", errors="replace")


def lua_quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t") + '"'


STRING_RE = re.compile(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')')


def decode_string_literals(text: str) -> tuple[str, int]:
    count = 0

    def repl(m):
        nonlocal count
        token = m.group(0)
        body = token[1:-1]
        decoded = lua_unescape(body)
        if decoded != body or "\\" in token:
            count += 1
        return lua_quote(decoded)

    return STRING_RE.sub(repl, text), count


CHAR_RE = re.compile(r"string\.char\(([^()]*)\)")


def decode_string_char(text: str) -> tuple[str, int]:
    count = 0

    def repl(m):
        nonlocal count
        parts = [p.strip() for p in m.group(1).split(",") if p.strip()]
        try:
            chars = []
            for part in parts:
                val = eval_num_expr(part)
                if abs(val - round(val)) > 1e-9:
                    raise ValueError(part)
                chars.append(int(round(val)) & 0xFF)
            count += 1
            return lua_quote(bytes(chars).decode("utf-8", errors="replace"))
        except Exception:
            return m.group(0)

    return CHAR_RE.sub(repl, text), count


REVERSE_RE = re.compile(r"(?:\((\"(?:\\.|[^\"\\])*\")\)|(\"(?:\\.|[^\"\\])*\")):reverse\(\)")


def decode_reverse(text: str) -> tuple[str, int]:
    count = 0

    def repl(m):
        nonlocal count
        token = m.group(1) or m.group(2)
        value = lua_unescape(token[1:-1])
        count += 1
        return lua_quote(value[::-1])

    return REVERSE_RE.sub(repl, text), count


CONCAT_RE = re.compile(r"(\"(?:\\.|[^\"\\])*\")\s*\.\.\s*(\"(?:\\.|[^\"\\])*\")")


def merge_string_concat(text: str) -> tuple[str, int]:
    total = 0
    while True:
        changed = 0

        def repl(m):
            nonlocal changed
            left = lua_unescape(m.group(1)[1:-1])
            right = lua_unescape(m.group(2)[1:-1])
            changed += 1
            return lua_quote(left + right)

        text = CONCAT_RE.sub(repl, text)
        total += changed
        if changed == 0:
            return text, total


BOOL_RE = re.compile(r"\((\s*-?[0-9][0-9+\-*/%().\s]*(?:==|~=|<=|>=|<|>)\s*-?[0-9][0-9+\-*/%().\s]*)\)")


def fold_booleans(text: str) -> tuple[str, int]:
    count = 0

    def repl(m):
        nonlocal count
        expr = m.group(1).replace("~=", "!=")
        try:
            val = eval_bool_expr(expr)
            count += 1
            return " true " if val else " false "
        except Exception:
            return m.group(0)

    return BOOL_RE.sub(repl, text), count



KNOWN_RENAMES = {
    "B__U__g_": "find_upvalue_recursive",
    "bU_G": "replace_upvalue_recursive",
    "__B__uG": "is_callback_from_source",
    "b_U__G_": "find_event_callback",
    "__bug_": "is_crimson_terrarium",
    "_BUg_": "bind_eye_cleanup_events",
    "__b__ug": "spawn_eye_prefab",
    "BU_G_": "get_non_admin_players",
    "_b_Ug__": "spawn_eye_near_random_player",
    "_bU_G": "shuffle_array",
    "__b_u__g": "find_closest_non_admin_player",
    "_bUg": "set_player_ghost_movement",
    "B__U__g__": "collect_equipment_snapshot",
    "_b_u_G__": "push_team_status_to_clients",
    "__b_Ug__": "set_team_status_subscription",
}


def apply_known_renames(text: str) -> tuple[str, int]:
    count = 0
    for old, new in sorted(KNOWN_RENAMES.items(), key=lambda item: len(item[0]), reverse=True):
        text, changed = re.subn(rf"\b{re.escape(old)}\b", new, text)
        count += changed
    return text, count

def rough_format(text: str) -> str:
    # Preserve strings by temporarily replacing them with sentinels.
    strings: list[str] = []

    def stash(m):
        strings.append(m.group(0))
        return f"@@STR{len(strings)-1}@@"

    work = STRING_RE.sub(stash, text)
    work = re.sub(r"\breturn\s*(true|false)\b", r"return \1", work)
    work = re.sub(r"\b(true|false)(?=(?:then|and|or)\b)", r"\1 ", work)
    work = re.sub(r"(?<=\bthen)(?=\S)", "\n", work)
    work = re.sub(r"(?<=\belse)(?=\S)", "\n", work)
    work = re.sub(r"\)\s*(Add[A-Za-z]+\()", r")\n\1", work)
    work = re.sub(r"\)\s*(modimport\()", r")\n\1", work)
    work = re.sub(r"\bend\s*(local\b)", r"end\n\1", work)
    work = re.sub(r"\bend\s*(function\b)", r"end\n\1", work)
    work = work.replace(";", ";\n")
    work = re.sub(r"\s+(local\s+function\s+)", r"\n\1", work)
    work = re.sub(r"\s+(function\s+)", r"\n\1", work)
    work = re.sub(r"\s+(Add[A-Za-z]+\()", r"\n\1", work)
    work = re.sub(r"\s+(modimport\()", r"\n\1", work)
    work = re.sub(r"\s+(if\s+)", r"\n\1", work)
    work = re.sub(r"\s+(elseif\s+)", r"\n\1", work)
    work = re.sub(r"\s+(else\b)", r"\n\1", work)
    work = re.sub(r"\s+(for\s+)", r"\n\1", work)
    work = re.sub(r"\s+(while\s+)", r"\n\1", work)
    work = re.sub(r"\s+(return\b)", r"\n\1", work)
    work = re.sub(r"\s+(end\b)", r"\n\1", work)
    work = re.sub(r"\n{3,}", "\n\n", work)

    for i, s in enumerate(strings):
        work = work.replace(f"@@STR{i}@@", s)

    lines = [ln.rstrip() for ln in work.splitlines()]
    return "\n".join(lines).strip() + "\n"


def main() -> int:
    text = INPUT.read_text(encoding="utf-8", errors="replace")
    original_len = len(text)
    stats = {}

    first_passes = [
        ("string.char", decode_string_char),
        ("string literals", decode_string_literals),
    ]
    for name, fn in first_passes:
        text, count = fn(text)
        stats[name] = count

    iterative_passes = [
        ("reverse", decode_reverse),
        ("string concat", merge_string_concat),
        ("string literals", decode_string_literals),
        ("boolean folds", fold_booleans),
    ]
    for round_no in range(1, 8):
        round_total = 0
        for name, fn in iterative_passes:
            text, count = fn(text)
            stats[f"round {round_no} {name}"] = count
            round_total += count
        if round_total == 0:
            break

    text, count = apply_known_renames(text)
    stats["known renames"] = count

    formatted = rough_format(text)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(formatted, encoding="utf-8", newline="\n")

    summary = [
        "# Deobfuscation Summary",
        "",
        f"Input: `{INPUT.relative_to(REPO_ROOT)}`",
        f"Output: `{OUTPUT.relative_to(REPO_ROOT)}`",
        "",
        "This is a generated readable copy. It is not loaded by the mod yet.",
        "",
        "## Passes",
    ]
    for key, value in stats.items():
        summary.append(f"- {key}: {value}")
    summary.extend([
        "",
        "## Size",
        f"- original characters: {original_len}",
        f"- output characters: {len(formatted)}",
        "",
        "## Next Manual Steps",
        "- Identify feature blocks by `AddPrefabPostInit`, `AddComponentPostInit`, `AddClassPostConstruct`, `AddModRPCHandler`, and `modimport` calls.",
        "- Move one feature block at a time into `src/features/*.lua`.",
        "- Keep `modmain.lua` behavior unchanged until each extracted feature is tested.",
    ])
    SUMMARY.write_text("\n".join(summary) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUTPUT}")
    print(f"wrote {SUMMARY}")
    for key, value in stats.items():
        print(f"{key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
